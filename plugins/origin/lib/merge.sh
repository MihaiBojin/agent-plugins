# shellcheck shell=bash
#
# Merging a pull request, with a body somebody could read a year from now.
#
# The default squash body on both forges is the list of commits, which is a
# record of how the work happened rather than what it did - "wip", "fix lint",
# "address review comments", "actually fix lint". That list is already in the
# pull request; the commit that lands on the head branch is the one that has to
# survive without it.
#
# So this splits in two. The script gathers the material and performs the
# merge; the model, in `skills/merge/SKILL.md`, writes the prose. Trailers are the
# exception: `Fixes #123` closes an issue and `Co-authored-by:` gives somebody
# credit, so they are re-attached here after the fact rather than trusted to
# survive a rewrite.

merge_usage() {
  cat >&2 <<'USAGE'
origin merge [<number>] [flags]

  Merge a pull request, with a written body rather than a commit list.

  --gather              Print the material for a body as JSON, and stop
  --squash              Squash into one commit (the default)
  --merge | --rebase    The other two strategies
  --title <text>        Subject line; defaults to the pull request's title
  --body <text>         The body
  --body-file <path>    The body, from a file ("-" for standard input)
  --edit                Open the body in $EDITOR before merging
  --with-failing-checks Merge although named checks are failing
  --dry-run             Print what would be merged, and stop
  --yes                 Do not ask

  Seven things stop a merge. Only the first has a flag:

    these checks are failing        --with-failing-checks
    it is a draft                   asked at a terminal, and marked ready
    these checks have not finished  refused
    its checks are still running    refused
    it does not merge cleanly       refused
    blocked, a review or a rule     refused
    the forge reports it dirty      refused

  A failing check is a judgement somebody can make, having read it. An
  unfinished one is not a judgement anybody can make yet: `gh pr merge --auto`
  is what waiting is for.
USAGE
}

MERGE_TMPDIR=''
merge_cleanup() {
  [ -n "$MERGE_TMPDIR" ] && [ -d "$MERGE_TMPDIR" ] && rm -rf "$MERGE_TMPDIR"
  return 0
}

merge_main() {
  local number='' method='' title='' body='' body_file='' edit=0
  local gather=0 with_failing_checks=0 have_body=0 arg

  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      --gather)
        gather=1
        shift
        ;;
      --squash | --merge | --rebase)
        method="$arg"
        shift
        ;;
      --title)
        require_value --title "${@:2}"
        title="$2"
        shift 2
        ;;
      --body)
        require_value --body "${@:2}"
        body="$2"
        have_body=1
        shift 2
        ;;
      --body-file)
        require_value --body-file "${@:2}"
        body_file="$2"
        have_body=1
        shift 2
        ;;
      --edit)
        edit=1
        shift
        ;;
      # `gh pr merge --auto` queues a merge for the forge to run once the
      # checks pass. This one never waited for anything; it was --yes under a
      # name that promised otherwise.
      --auto)
        die "merge: --auto is gone - it meant --yes, and it read like gh pr merge --auto; pass --yes"
        ;;
      --with-failing-checks)
        with_failing_checks=1
        shift
        ;;
      --force)
        die "merge: --force is gone - it covered seven unrelated refusals with one word; pass --with-failing-checks for the only one a person can judge"
        ;;
      # The branch on the remote is the forge's. GitHub's "automatically
      # delete head branches" and GitLab's "delete source branch" already
      # decide it per repository, so there is nothing here to turn off.
      --no-delete-branch)
        die "merge: --no-delete-branch is gone - the remote branch is left alone either way; the forge's own setting decides whether it goes"
        ;;
      -h | --help)
        merge_usage
        return 0
        ;;
      -[0-9]*) die "merge: unknown flag ${arg}" ;;
      [0-9]*)
        number="$arg"
        shift
        ;;
      *) die "merge: unknown argument ${arg}" ;;
    esac
  done

  repo_require
  forge_require

  local policy allowed
  policy="$(forge_merge_policy)"
  allowed="${policy##* }"
  if [ -z "$method" ]; then
    method="--${policy%% *}"
    debug "using the repository's default merge method: ${method}"
  fi
  case ",${allowed}," in
    *",${method#--},"*) ;;
    *) die "this repository does not allow a ${method#--} merge; it allows ${allowed}" ;;
  esac

  trap merge_cleanup EXIT
  MERGE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/origin-merge.XXXXXX")"

  merge_load "$number"

  local pr_number pr_title pr_state head_ref base_ref
  pr_number="$(forge_pr_field .number)"
  pr_title="$(forge_pr_field .title)"
  pr_state="$(forge_pr_field .state)"
  head_ref="$(forge_pr_field .headRef)"
  base_ref="$(forge_pr_field .baseRef)"

  # The range the body is written from has to exist locally, and after a fetch
  # it usually does.
  repo_fetch

  # Before the refusals are read, and before `--gather` reports them: a gather
  # that says `could not determine whether it merges cleanly` about a pull
  # request the merge would settle and accept sends the model away for no
  # reason, and the two would be answering from different readings.
  merge_settle_mergeable "$pr_number"

  if [ "$gather" = 1 ]; then
    merge_gather
    return 0
  fi

  [ "$pr_state" = "OPEN" ] ||
    die "$(forge_noun) #${pr_number} is ${pr_state}; there is nothing to merge"

  local refusals
  refusals="$(merge_refusals)"

  if merge_has_kind draft "$refusals"; then
    if [ "$ORIGIN_DRY_RUN" = 1 ]; then
      note "would ask whether to mark #${pr_number} ready for review"
      refusals="$(printf '%s\n' "$refusals" | grep -v "^draft${ORIGIN_FS}" || printf '')"
    else
      merge_undraft "$pr_number"
      # Everything is read again. Marking a draft ready can start required
      # checks and request reviews it never had, so a pull request refused only
      # for being a draft can come back refused for a pending check - which is
      # the right answer, not a bug.
      merge_settle_mergeable "$pr_number"
      refusals="$(merge_refusals)"
    fi
  fi

  if [ -n "$refusals" ]; then
    say ''
    warn "$(forge_noun) #${pr_number} is not ready to merge:"
    printf '%s\n' "$refusals" | cut -d"$ORIGIN_FS" -f2- | indent_lines
    say ''
    # Anything that is not a failing check is the end of it. One flag covering
    # seven unrelated refusals is what `--force` was, and the reason a merge
    # could get past a blocked review by naming a check.
    if printf '%s\n' "$refusals" | cut -d"$ORIGIN_FS" -f1 | grep -qv '^checks$'; then
      die "refusing to merge; no flag gets past that"
    fi
    [ "$with_failing_checks" = 1 ] ||
      die "refusing to merge; pass --with-failing-checks if you have read them and mean it"
    warn "merging anyway, because --with-failing-checks"
  fi

  # The body: whatever was passed, or a plain one built from what is already
  # written down. The bullets are the model's job and this is what happens
  # without one.
  if [ -n "$body_file" ]; then
    if [ "$body_file" = "-" ]; then
      body="$(cat)"
    else
      [ -r "$body_file" ] || die "merge: cannot read ${body_file}"
      body="$(cat "$body_file")"
    fi
  elif [ "$have_body" = 0 ]; then
    body="$(merge_fallback_body)"
  fi

  [ -n "$title" ] || title="$pr_title"
  title="$(merge_decorate_title "$title" "$pr_number" "$method")"

  # Trailers are load-bearing and a rewrite is where they go missing, so they
  # are put back rather than checked for.
  body="$(merge_reattach_trailers "$body")"

  if [ "$edit" = 1 ]; then
    # An editor with nowhere to open is a command that hangs, which is the one
    # thing an agent invocation must never do.
    have_tty || die "--edit needs a terminal to open an editor in"
    body="$(merge_edit "$title" "$body")"
  fi

  local body_path="${MERGE_TMPDIR}/body"
  printf '%s\n' "$body" >"$body_path"

  say ''
  say "${C_BOLD}${title}${C_OFF}"
  say ''
  printf '%s\n' "$body" | indent_lines '  '
  say ''

  local plan="${method#--}"

  confirm "Merge #${pr_number} into ${base_ref} (${plan})?" \
    "$(forge_cli) merge #${pr_number} ${method} with the title and body above" \
    "leave ${head_ref} alone; whether it goes is the forge's setting to apply"

  forge_pr_merge "$pr_number" "$method" --title "$title" --body-file "$body_path" ||
    die "the merge was refused by $(forge_cli)"
  good "merged #${pr_number}"
}

# Either the number given, or the one belonging to the branch in hand.
merge_load() {
  local number="$1" branch
  if [ -n "$number" ]; then
    forge_pr_load_number "$number" ||
      die "there is no $(forge_noun) #${number}"
    return 0
  fi
  branch="$(repo_current_branch)"
  [ -n "$branch" ] || die "HEAD is detached; say which $(forge_noun) to merge"
  forge_pr_load "$branch" ||
    die "no open $(forge_noun) for ${branch}; say which one to merge"
}

merge_has_kind() {
  printf '%s\n' "$2" | grep -q "^${1}${ORIGIN_FS}"
}

# Waits for the forge to work out whether it merges cleanly.
#
# Both forges compute mergeability asynchronously: a pull request read moments
# after a push answers UNKNOWN and answers properly a moment later. Refusing on
# the first UNKNOWN would reject perfectly mergeable work at random, which
# reads as flaky rather than careful.
#
# Three tries, two seconds apart. Both numbers are a guess - nothing here has
# been measured against a live pull request, and that is the thing to do before
# trusting them. The two variables exist so a test does not sleep.
merge_settle_mergeable() {
  local number="$1" tries="${ORIGIN_MERGEABLE_TRIES:-3}" wait="${ORIGIN_MERGEABLE_WAIT:-2}" try=1
  while [ "$(forge_pr_field .mergeable)" = "UNKNOWN" ] && [ "$try" -lt "$tries" ]; do
    note "the forge has not said whether it merges cleanly yet; asking again"
    if [ "$wait" -gt 0 ]; then
      sleep "$wait"
    fi
    forge_pr_load_number "$number" || break
    try=$((try + 1))
  done
  return 0
}

# A draft is a question rather than a refusal: the answer is usually "yes, it
# is ready", and that is one command away.
#
# --yes does not answer it. Marking a draft ready changes the pull request -
# starting required checks, requesting reviews - rather than performing one of
# the ordinary steps --yes is there to skip.
merge_undraft() {
  local number="$1" reply how
  if ! have_tty; then
    case "$(forge_kind)" in
      github) how="gh pr ready ${number}" ;;
      gitlab) how="glab mr update ${number} --ready" ;;
      *) how="mark it ready on the forge" ;;
    esac
    die "$(forge_noun) #${number} is a draft, and there is no terminal to ask at; mark it ready with: ${how}"
  fi
  say ''
  say "$(forge_noun) #${number} is a draft."
  printf 'Mark it ready for review? [y/N] ' >&2
  read -r reply </dev/tty || reply=''
  case "$reply" in
    y | Y | yes | Yes | YES) ;;
    *) die "aborted" ;;
  esac
  forge_pr_mark_ready "$number"
}

# Why not to merge: a kind, then the reason, one per line.
#
# The kind decides what can get past it. `checks` is the one a person can judge
# - they have read the failure and decided it does not matter - and
# `--with-failing-checks` is how they say so. `draft` is a question rather than
# a refusal. Everything else is `hard`, and nothing overrides it.
merge_refusals() {
  local checks pending
  [ "$(forge_pr_field .draft)" = "true" ] && printf 'draft%sit is a draft\n' "$ORIGIN_FS"
  # Positively MERGEABLE, rather than "not CONFLICTING". Both forges compute
  # this asynchronously and answer UNKNOWN until they have, and a field the
  # forge never sent arrives here as UNKNOWN too - so treating anything but a
  # conflict as safe merged on an answer nobody had given.
  case "$(forge_pr_field .mergeable)" in
    MERGEABLE) ;;
    CONFLICTING) printf 'hard%sit conflicts with %s\n' "$ORIGIN_FS" "$(forge_pr_field .baseRef)" ;;
    *) printf 'hard%scould not determine whether it merges cleanly\n' "$ORIGIN_FS" ;;
  esac
  case "$(forge_pr_field .mergeStateStatus)" in
    BLOCKED) printf 'hard%sthe forge reports it blocked - a review, or a branch protection rule\n' "$ORIGIN_FS" ;;
    DIRTY) printf 'hard%sthe forge reports the merge dirty\n' "$ORIGIN_FS" ;;
  esac
  checks="$(printf '%s' "$FORGE_PR_JSON" | jq -r '.failingChecks | join(", ")')"
  [ -n "$checks" ] && printf 'checks%sthese checks are failing: %s\n' "$ORIGIN_FS" "$checks"
  # One reading, taken now. A check still running is a reason not to merge
  # rather than a reason to sit and poll: the answer arrives minutes after the
  # command would have returned, and `gh pr merge --auto` is what waiting is
  # for. The forge's own word is the fallback for a pipeline it will not name.
  pending="$(printf '%s' "$FORGE_PR_JSON" | jq -r '(.pendingChecks // []) | join(", ")')"
  if [ -n "$pending" ]; then
    printf 'hard%sthese checks have not finished: %s\n' "$ORIGIN_FS" "$pending"
  elif [ "$(forge_pr_field .mergeStateStatus)" = "PENDING" ]; then
    printf 'hard%sthe forge reports its checks still running\n' "$ORIGIN_FS"
  fi
  return 0
}

# The reasons alone, as a person reads them. The gate cuts the kinds off the
# list it already has rather than calling this: `merge_refusals` asks the forge
# object several questions, and a second reading could disagree with the one
# the decision was made from.
merge_refusal_reasons() {
  merge_refusals | cut -d"$ORIGIN_FS" -f2-
}

# Everything a body could be written from, in one object.
merge_gather() {
  local commits diffstat trailers fallback_title fallback_body refusals stacked=false
  commits="$(forge_pr_commits "$(forge_pr_field .number)")"
  diffstat="$(forge_pr_diffstat "$(forge_pr_field .number)")"
  trailers="$(merge_trailers)"
  fallback_title="$(merge_decorate_title "$(forge_pr_field .title)" "$(forge_pr_field .number)" --squash)"
  fallback_body="$(merge_fallback_body)"
  refusals="$(merge_refusal_reasons | json_array_from_lines)"
  # Asked here so it is known before a word of the body is written, rather than
  # found out by the merge failing after the user has approved one.
  if forge_pr_stacked "$(forge_pr_field .number)"; then
    stacked=true
  fi

  jq -n \
    --argjson pr "$FORGE_PR_JSON" \
    --argjson commits "$commits" \
    --argjson diffstat "$diffstat" \
    --argjson trailers "$trailers" \
    --argjson refusals "$refusals" \
    --argjson stacked "$stacked" \
    --arg fallbackTitle "$fallback_title" \
    --arg fallbackBody "$fallback_body" \
    '{
      pr: $pr,
      commits: $commits,
      diffstat: $diffstat,
      trailers: $trailers,
      refusals: $refusals,
      stacked: $stacked,
      fallback: { title: $fallbackTitle, body: $fallbackBody }
    }'
}

# The description as GitHub would scan it for a closing keyword: fenced blocks
# and inline code removed, because a reference inside backticks is not a link
# and closes nothing. Documentation that explains `Fixes #123` is otherwise
# read as fixing issue 123.
merge_prose() {
  forge_pr_field .body | awk '
    /^[[:space:]]*```/ { fenced = !fenced; next }
    fenced { next }
    { gsub(/`[^`]*`/, ""); print }
  '
}

# One trailer token from the trailer block of every commit in the range.
#
# Read with `%(trailers:key=…)` rather than grepped: a trailer is the block at
# the end of a message, and a commit that merely writes `Co-authored-by:` in a
# sentence has not given anybody credit.
merge_commit_trailers() {
  local token="$1" range base head number
  number="$(forge_pr_field .number)"

  if range="$(forge_pr_range)"; then
    base="${range%% *}"
    head="${range##* }"
    git log --format="%(trailers:key=${token},valueonly,unfold)" "${base}..${head}" 2>/dev/null |
      grep -v '^[[:space:]]*$' || true
    return 0
  fi

  forge_pr_api_commits "$number" |
    jq -r '.[] | .subject + "\n\n" + .body + "\u0000"' |
    while IFS= read -r -d '' message; do
      printf '%s\n' "$message" |
        git interpret-trailers --parse 2>/dev/null |
        awk -v token="${token}:" 'index(tolower($0), tolower(token)) == 1 { sub(/^[^:]*:[[:space:]]*/, ""); print }'
    done
}

# `Fixes #123` closes an issue and `Co-authored-by:` gives somebody credit.
# Both stop working the moment they are paraphrased, so both are put back after
# the body is written. They are read differently because they are different
# things: a closing keyword is prose GitHub scans, a co-author is a git trailer.
merge_trailers() {
  local issues coauthors

  issues="$(merge_prose |
    grep -Eio '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' |
    awk '{ key = tolower($0); if (!seen[key]++) print }' || true)"

  coauthors="$(merge_commit_trailers Co-authored-by |
    awk '{ key = tolower($0); if (!seen[key]++) print }' || true)"

  printf '{%s,%s}\n' \
    "$(json_raw_field issues "$(printf '%s\n' "$issues" | json_array_from_lines)")" \
    "$(json_raw_field coAuthors "$(printf '%s\n' "$coauthors" | json_array_from_lines)")"
}

# What the body is when nobody writes one: the description, and the trailers.
#
# No bullets, because inventing them is exactly what a script must not do.
merge_fallback_body() {
  local description
  description="$(forge_pr_field .body)"
  # Drop the HTML comment template, which is most of an unedited pull request
  # body and none of its meaning.
  description="$(printf '%s\n' "$description" | awk '
    /<!--/ { inside = 1 }
    inside == 0 { print }
    /-->/ { inside = 0 }
  ')"
  description="$(printf '%s\n' "$description" | sed -e 's/[[:space:]]*$//')"
  printf '%s\n' "$description"
}

# Text reduced to lowercase words separated by single spaces.
#
# Everything that is not a letter, a digit or an underscore becomes a space, so
# a comparison can only match whole words: `#1` and `#12` both lose the `#` and
# become `1` and `12`, which no longer share a boundary.
merge_squeeze() {
  printf '%s' "${1-}" |
    tr '[:upper:]' '[:lower:]' |
    tr -c '[:alnum:]_' ' ' |
    tr -s ' '
}

# Does the body already carry this trailer?
#
# Word by word rather than by substring: `Fixes #1` is a substring of
# `Fixes #12`, and a body that mentions issue 12 would otherwise be read as
# already closing issue 1 - which is how the trailer that closes it goes
# missing from the merge commit, silently, in the one place that exists to stop
# that happening.
merge_body_has() {
  local haystack needle
  haystack=" $(merge_squeeze "$1") "
  needle=" $(merge_squeeze "$2") "
  case "$haystack" in
    *"$needle"*) return 0 ;;
  esac
  return 1
}

# Puts back every trailer the material had, that the body now lacks.
merge_reattach_trailers() {
  local body="$1" trailers issues coauthors line missing=''

  trailers="$(merge_trailers)"
  issues="$(printf '%s' "$trailers" | jq -r '.issues[]?')"
  coauthors="$(printf '%s' "$trailers" | jq -r '.coAuthors[]?')"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    merge_body_has "$body" "$line" || missing="${missing}${line}"$'\n'
  done <<EOF
$issues
EOF

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    merge_body_has "$body" "$line" ||
      missing="${missing}Co-authored-by: ${line}"$'\n'
  done <<EOF
$coauthors
EOF

  if [ -z "$missing" ]; then
    printf '%s\n' "$body"
    return 0
  fi
  printf '%s\n\n%s' "$body" "$missing"
}

# The subject carries a reference back to the request. GitHub autolinks `#12`,
# GitLab autolinks `!12`; GitHub adds its own when it composes a squash subject
# and stops when one is passed, and GitLab never adds one.
merge_decorate_title() {
  local title="$1" number="$2" method="$3" mark
  [ "$method" = "--squash" ] || {
    printf '%s\n' "$title"
    return 0
  }
  case "$(forge_kind)" in
    github) mark="#" ;;
    gitlab) mark="!" ;;
    *)
      printf '%s\n' "$title"
      return 0
      ;;
  esac
  case "$title" in
    *"(${mark}${number})"*) printf '%s\n' "$title" ;;
    *) printf '%s (%s%s)\n' "$title" "$mark" "$number" ;;
  esac
}

merge_edit() {
  local title="$1" body="$2" file="${MERGE_TMPDIR}/EDITMSG" editor
  editor="${ORIGIN_EDITOR:-${GIT_EDITOR:-${VISUAL:-${EDITOR:-}}}}"
  [ -n "$editor" ] || editor="$(git config --get core.editor || printf 'vi')"

  {
    printf '%s\n' "$body"
    printf '\n# The subject line is: %s\n' "$title"
    printf '# Lines starting with # are dropped. An empty body aborts.\n'
  } >"$file"

  # Split like git splits core.editor, so `code --wait` works.
  # shellcheck disable=SC2086
  $editor "$file" </dev/tty >/dev/tty 2>&1 || die "the editor exited badly"

  local edited
  edited="$(grep -v '^#' "$file" | sed -e 's/[[:space:]]*$//')"
  edited="$(printf '%s\n' "$edited" | sed -e '/./,$!d')"
  [ -n "$edited" ] || die "the body is empty; nothing merged"
  printf '%s\n' "$edited"
}
