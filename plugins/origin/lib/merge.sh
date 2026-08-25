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
# merge; the model, in `commands/merge.md`, writes the prose. Trailers are the
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
  --force               Merge anyway, having been told why not
  --no-delete-branch    Leave the remote branch alone
  --dry-run             Print what would be merged, and stop
  --yes                 Do not ask
USAGE
}

MERGE_TMPDIR=''
merge_cleanup() {
  [ -n "$MERGE_TMPDIR" ] && [ -d "$MERGE_TMPDIR" ] && rm -rf "$MERGE_TMPDIR"
  return 0
}

merge_main() {
  local number='' method='' title='' body='' body_file='' edit=0
  local gather=0 force=0 delete_branch=1 have_body=0 arg

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
      --force)
        force=1
        shift
        ;;
      --no-delete-branch)
        delete_branch=0
        shift
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

  if [ "$gather" = 1 ]; then
    merge_gather
    return 0
  fi

  [ "$pr_state" = "OPEN" ] ||
    die "$(forge_noun) #${pr_number} is ${pr_state}; there is nothing to merge"

  local refusals
  refusals="$(merge_refusals)"
  if [ -n "$refusals" ]; then
    say ''
    warn "$(forge_noun) #${pr_number} is not ready to merge:"
    printf '%s\n' "$refusals" | indent_lines
    say ''
    [ "$force" = 1 ] || die "refusing to merge; pass --force if you mean it"
    warn "merging anyway, because --force"
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

  local plan="${method#--}" remote branch_plan head_sha=''
  remote="$(repo_remote 2>/dev/null || printf '')"
  # Read before the merge, because after it the branch may be gone from the
  # forge and this is the only thing that says where it was.
  [ -n "$remote" ] &&
    head_sha="$(git rev-parse --short "refs/remotes/${remote}/${head_ref}" 2>/dev/null || printf '')"

  if [ "$(forge_pr_field .crossRepository)" = "true" ]; then
    # Left to `merge_delete_remote_branch`, which refuses it and says so out
    # loud - the confirmation is silent under --yes, and this is worth saying.
    branch_plan="leave ${head_ref} alone; it is a fork's branch"
  elif [ "$delete_branch" = 1 ] && [ -n "$remote" ] && [ -n "$head_sha" ]; then
    branch_plan="git push ${remote} --delete ${head_ref}"
    losing "This will delete:" \
      "${remote}/${head_ref} (${head_sha}) — restore with: git push ${remote} ${head_sha}:refs/heads/${head_ref}"
  else
    # No sha to name means no way to say how to put it back, so it stays.
    [ "$delete_branch" = 1 ] && [ -n "$remote" ] &&
      warn "not deleting ${remote}/${head_ref}: nothing here records the sha that would restore it"
    delete_branch=0
    branch_plan="keep ${remote:+${remote}/}${head_ref}"
  fi

  confirm "Merge #${pr_number} into ${base_ref} (${plan})?" \
    "$(forge_cli) merge #${pr_number} ${method} with the title and body above" \
    "$branch_plan"

  forge_pr_merge "$pr_number" "$method" --title "$title" --body-file "$body_path" ||
    die "the merge was refused by $(forge_cli)"
  good "merged #${pr_number}"

  if [ "$delete_branch" = 1 ]; then
    merge_delete_remote_branch "$head_ref" "$head_sha"
  fi

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

# Why not to merge, one reason per line. Empty means go ahead.
merge_refusals() {
  local checks pending
  [ "$(forge_pr_field .draft)" = "true" ] && printf 'it is a draft\n'
  case "$(forge_pr_field .mergeable)" in
    CONFLICTING) printf 'it conflicts with %s\n' "$(forge_pr_field .baseRef)" ;;
  esac
  case "$(forge_pr_field .mergeStateStatus)" in
    BLOCKED) printf 'the forge reports it blocked - a review, or a branch protection rule\n' ;;
    DIRTY) printf 'the forge reports the merge dirty\n' ;;
  esac
  checks="$(printf '%s' "$FORGE_PR_JSON" | jq -r '.failingChecks | join(", ")')"
  [ -n "$checks" ] && printf 'these checks are failing: %s\n' "$checks"
  # One reading, taken now. A check still running is a reason not to merge
  # rather than a reason to sit and poll: the answer arrives minutes after the
  # command would have returned, and `gh pr merge --auto` is what waiting is
  # for. The forge's own word is the fallback for a pipeline it will not name.
  pending="$(printf '%s' "$FORGE_PR_JSON" | jq -r '(.pendingChecks // []) | join(", ")')"
  if [ -n "$pending" ]; then
    printf 'these checks have not finished: %s\n' "$pending"
  elif [ "$(forge_pr_field .mergeStateStatus)" = "PENDING" ]; then
    printf 'the forge reports its checks still running\n'
  fi
  return 0
}

# Everything a body could be written from, in one object.
merge_gather() {
  local commits diffstat trailers fallback_title fallback_body refusals
  commits="$(forge_pr_commits "$(forge_pr_field .number)")"
  diffstat="$(forge_pr_diffstat "$(forge_pr_field .number)")"
  trailers="$(merge_trailers)"
  fallback_title="$(merge_decorate_title "$(forge_pr_field .title)" "$(forge_pr_field .number)" --squash)"
  fallback_body="$(merge_fallback_body)"
  refusals="$(merge_refusals | json_array_from_lines)"

  jq -n \
    --argjson pr "$FORGE_PR_JSON" \
    --argjson commits "$commits" \
    --argjson diffstat "$diffstat" \
    --argjson trailers "$trailers" \
    --argjson refusals "$refusals" \
    --arg fallbackTitle "$fallback_title" \
    --arg fallbackBody "$fallback_body" \
    '{
      pr: $pr,
      commits: $commits,
      diffstat: $diffstat,
      trailers: $trailers,
      refusals: $refusals,
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

# The branch on the remote, once nothing points at it.
#
# A pull request from a fork is left alone. Its head branch lives in somebody
# else's repository, and `headRef` carries the bare name, so a fork's `main`
# and this repository's `main` are one string - the forge is the only thing
# that can tell them apart, and a remote-tracking ref matching the name is
# evidence of nothing.
merge_delete_remote_branch() {
  local branch="$1" sha="${2:-}" remote
  if [ "$(forge_pr_field .crossRepository)" = "true" ]; then
    note "#$(forge_pr_field .number) came from a fork; leaving ${branch} alone"
    return 0
  fi
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$remote" ] || return 0
  if ! git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"; then
    note "${remote} has no ${branch} to delete"
    return 0
  fi
  # The same rule the local branch delete follows: no recorded sha, no
  # deletion. A branch on a remote is harder to get back, not easier.
  [ -n "$sha" ] || {
    warn "not deleting ${remote}/${branch}: nothing here records the sha that would restore it"
    return 0
  }
  git_run push "$remote" --delete "$branch" || {
    warn "could not delete ${remote}/${branch}; it may already be gone"
    return 0
  }
  say "deleted ${remote}/${branch} (was ${sha})"
  say "  restore: git push ${remote} ${sha}:refs/heads/${branch}"
}
