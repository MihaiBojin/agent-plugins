# shellcheck shell=bash
#
# Worktrees: making one, listing them, removing a finished one.
#
# Every worktree of every repository under one parent directory lives at
#
#     <PARENT>/.worktrees/<branch>/<repo>
#
# where PARENT holds the main checkout. Repositories side by side share the
# root, one <repo> directory each, so the same branch name in several of them
# groups their worktrees together. A slash in a branch name nests.

# `repo_require`, plus the main worktree resolved in this shell. `worktree_root`
# and `worktree_path_for` both read it through `$(…)`, and a subshell would take
# the cached answer with it; warming it here means the two of them cost one
# `git worktree list` between them rather than one each. Only the three
# worktree commands need it, so only they pay for it.
worktree_require() {
  repo_require
  ORIGIN_MAIN_WORKTREE="$(repo_main_worktree || printf '')"
}

worktree_root() {
  printf '%s/.worktrees\n' "$(dirname "$(repo_main_worktree)")"
}

worktree_path_for() {
  printf '%s/%s/%s\n' "$(worktree_root)" "$1" "$(repo_name)"
}

# One line per worktree: path, sha, branch, flags.
worktree_records() {
  local line path='' sha='' branch='' flags=''
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "HEAD "*) sha="${line#HEAD }" ;;
      "branch "*)
        branch="${line#branch }"
        branch="${branch#refs/heads/}"
        ;;
      bare) flags="${flags}bare," ;;
      detached) flags="${flags}detached," ;;
      locked*) flags="${flags}locked," ;;
      prunable*) flags="${flags}prunable," ;;
      '')
        if [ -n "$path" ]; then
          printf '%s%s%s%s%s%s%s\n' "$path" "$ORIGIN_FS" "$sha" "$ORIGIN_FS" "$branch" "$ORIGIN_FS" "${flags%,}"
        fi
        path='' sha='' branch='' flags=''
        ;;
    esac
  done <<EOF
$(git worktree list --porcelain)
EOF
  if [ -n "$path" ]; then
    printf '%s%s%s%s%s%s%s\n' "$path" "$ORIGIN_FS" "$sha" "$ORIGIN_FS" "$branch" "$ORIGIN_FS" "${flags%,}"
  fi
  return 0
}

# A here-doc rather than a pipe, in these three and for one reason: awk's `exit`
# closes its stdin while worktree_records is still writing, so the writer takes
# SIGPIPE, pipefail turns that into 141, and `set -e` exits the program with no
# output at all. It starts once there are more worktrees than a pipe buffer's
# worth of records ahead of the match.
worktree_path_of_branch() {
  awk -F'\037' -v branch="$1" '$3 == branch { print $1; exit }' <<EOF
$(worktree_records)
EOF
}

worktree_branch_at() {
  awk -F'\037' -v path="$1" '$1 == path { print $3; exit }' <<EOF
$(worktree_records)
EOF
}

# The whole record for one path - sha, branch and flags in one line - or
# nothing when this repository has no worktree there. Nothing is the answer to
# "is this ours", which an empty branch alone cannot give: a detached worktree
# has one too.
worktree_record_at() {
  awk -F'\037' -v path="$1" '$1 == path { print; exit }' <<EOF
$(worktree_records)
EOF
}

worktree_record_field() {
  printf '%s\n' "$1" | awk -F'\037' -v n="$2" '{ print $n }'
}

# shellcheck disable=SC2088  # the tilde is being printed
worktree_pretty_path() {
  case "$1" in
    "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# The root is a parameter because a caller with rows to name has it already:
# working it out costs a `git worktree list --porcelain` of its own, and a
# table of thirty worktrees would run thirty of them.
worktree_display_name() {
  local root="${2:-}"
  [ -n "$root" ] || root="$(worktree_root)"
  case "$1" in
    "$root"/*) printf '%s\n' "${1#"$root"/}" ;;
    *) basename "$1" ;;
  esac
}

# --------------------------------------------------------------------------
# Who owns a destination
# --------------------------------------------------------------------------

# The git directory of whatever repository owns `$1`, or nothing.
#
# Asked of git rather than read out of `git worktree list`: that list holds
# this repository's worktrees only, so a directory belonging to a different
# repository looks unoccupied in it.
worktree_owner() {
  [ -d "$1" ] || return 1
  git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null
}

# `free`, `ours`, or `blocked:<reason>`.
#
# Three positions, one question: who owns this directory. The destination may
# be a worktree itself, it may sit inside one, or it may be an unrelated
# non-empty directory because another branch nests under it. `git worktree
# list` answers none of them, because it holds this repository's worktrees only
# and a squatter belongs to a different one.
worktree_dest_state() {
  local dest="$1" ours boundary candidate parent owner bounded=0
  ours="$(repo_common_dir)"
  boundary="$(worktree_root)"

  # Inside the worktree root the walk is bounded there: PARENT is often a
  # repository of its own, and an unbounded walk would find it and refuse every
  # destination. A path named outright with --path is not under the root, so
  # for that one the nearest existing ancestor is as far as it goes.
  case "$dest" in
    "$boundary"/*) bounded=1 ;;
  esac

  if [ -e "$dest" ] && [ ! -d "$dest" ]; then
    printf 'blocked:%s is a file\n' "$dest"
    return 0
  fi

  candidate="$dest"
  while :; do
    if [ -d "$candidate" ]; then
      owner="$(worktree_owner "$candidate" || printf '')"
      if [ -n "$owner" ]; then
        if [ "$owner" != "$ours" ]; then
          printf 'blocked:%s belongs to another repository (%s)\n' "$candidate" "$owner"
        elif [ "$candidate" = "$dest" ]; then
          printf 'ours\n'
        else
          printf 'blocked:%s is already a worktree of this repository (%s)\n' \
            "$candidate" "$(worktree_branch_at "$candidate")"
        fi
        return 0
      fi
      if [ "$candidate" = "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
        printf 'blocked:%s already exists and is not empty\n' "$dest"
        return 0
      fi
      [ "$bounded" = 1 ] || break
    fi

    [ "$bounded" = 1 ] && [ "$candidate" = "$boundary" ] && break
    parent="$(dirname "$candidate")"
    [ "$parent" = "$candidate" ] && break
    candidate="$parent"
    if [ "$bounded" = 1 ]; then
      case "$candidate" in
        "$boundary" | "$boundary"/*) ;;
        *) break ;;
      esac
    fi
  done

  printf 'free\n'
}

# --------------------------------------------------------------------------
# add
# --------------------------------------------------------------------------

# Where this branch's worktree is. A shell function whose whole job is to `cd`
# there needs the path alone on stdout, so the reason there is not one goes to
# stderr and the exit code carries the answer.
worktree_path() {
  local branch='' arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      -h | --help)
        cat >&2 <<'USAGE'
origin git-worktree path <branch>   (aliases: gw path, gwp)

Print the path of the worktree that has <branch> checked out. Exit 1 when no
worktree of this repository has it.
USAGE
        return 0
        ;;
      -*) die "git-worktree path: unknown argument ${arg}" ;;
      *)
        [ -z "$branch" ] ||
          die "git-worktree path: one branch at a time, not '${branch}' and '${arg}'"
        branch="$arg"
        shift
        ;;
    esac
  done

  [ -n "$branch" ] || die "git-worktree path: which branch?"

  repo_require

  local path
  path="$(worktree_path_of_branch "$branch")"
  [ -n "$path" ] ||
    die "no worktree of this repository has ${branch} checked out"

  printf '%s\n' "$path"
}

worktree_add_usage() {
  cat >&2 <<'USAGE'
origin git-worktree add <branch> [flags]      (aliases: gw add, gwa)

  --base <ref>   Branch from this instead of the head branch
  --path <dir>   Put the worktree here instead of <PARENT>/.worktrees/<branch>/<repo>
  --dry-run      Say what would happen
  --quiet        Print the path and nothing else
USAGE
}

worktree_add() {
  local branch='' path='' base='' arg

  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      --path)
        require_value --path "${@:2}"
        path="$2"
        shift 2
        ;;
      --base)
        require_value --base "${@:2}"
        base="$2"
        shift 2
        ;;
      -h | --help)
        worktree_add_usage
        return 0
        ;;
      -*) die "git-worktree add: unknown flag ${arg}" ;;
      *)
        [ -z "$branch" ] || die "git-worktree add: one branch at a time (got '${branch}' and '${arg}')"
        branch="$arg"
        shift
        ;;
    esac
  done
  [ -n "$branch" ] || die "git-worktree add: which branch? usage: origin gwa <branch>"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 ||
    die "git-worktree add: '${branch}' is not a valid branch name"

  worktree_require

  local existing
  existing="$(worktree_path_of_branch "$branch")"
  if [ -n "$existing" ]; then
    note "${branch} already has a worktree"
    printf '%s\n' "$existing"
    return 0
  fi

  repo_fetch

  local remote
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$base" ] || base="$(repo_head_ref)"

  if [ -n "$path" ]; then
    path="$(repo_resolve_path "$path")"
  else
    path="$(worktree_path_for "$branch")"
  fi

  local state
  state="$(worktree_dest_state "$path")"
  case "$state" in
    ours)
      note "${path} is already a worktree of this repository"
      printf '%s\n' "$path"
      return 0
      ;;
    blocked:*) die "git-worktree add: ${state#blocked:}" ;;
  esac

  # What the success line says, decided by the branch that ran rather than by
  # the head branch, which two of these three never touch.
  local origin_of=''
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    note "Checking out ${branch}"
    # The bare name, not `refs/heads/${branch}`: `git worktree add` reads a
    # bare name as a branch to check out and a full ref as a commit to detach
    # at, and it prefers the branch over a tag of the same name already.
    git_run worktree add "$path" "$branch"
  elif [ -n "$remote" ] && git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"; then
    note "Checking out ${remote}/${branch}"
    git_run worktree add --track -b "$branch" "$path" "refs/remotes/${remote}/${branch}"
    origin_of=" (tracking ${remote}/${branch})"
  else
    git rev-parse --verify --quiet "${base}^{commit}" >/dev/null ||
      die "git-worktree add: $(ref_name "$base") is not a commit to branch from"
    note "Branching ${branch} from $(ref_name "$base")"
    # --no-track: a new branch off <remote>/<head> would otherwise take the
    # head branch as its upstream, and `git push` would target it.
    git_run worktree add --no-track -b "$branch" "$path" "$base"
    origin_of=" (from $(ref_name "$base"))"
  fi

  good "${branch} at $(worktree_pretty_path "$path")${origin_of}"
  printf '%s\n' "$path"
}

# --------------------------------------------------------------------------
# list
# --------------------------------------------------------------------------

worktree_is_dirty() {
  [ -d "$1" ] || return 1
  [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]
}

# `%cI` and `%cr` for one commit, into ORIGIN_COMMIT_ISO and ORIGIN_COMMIT_AGE.
#
# Two globals rather than a printed pair, because a caller writing
# `$(worktree_commit_age ...)` would run this in a subshell and the cache would
# die with it. One `git log` covers both fields, and worktrees sharing a commit
# - every one just branched from the head branch - share the answer.
ORIGIN_COMMIT_CACHE=''
ORIGIN_COMMIT_ISO=''
ORIGIN_COMMIT_AGE=''

worktree_commit_age() {
  local sha="$1" hit line
  ORIGIN_COMMIT_ISO='' ORIGIN_COMMIT_AGE=''
  [ -n "$sha" ] || return 0

  hit="${ORIGIN_COMMIT_CACHE#*"${ORIGIN_FS}${sha}${ORIGIN_FS}"}"
  if [ "$hit" = "$ORIGIN_COMMIT_CACHE" ]; then
    line="$(git log -1 --format="%cI${ORIGIN_FS}%cr" "$sha" 2>/dev/null || printf '')"
    ORIGIN_COMMIT_CACHE="${ORIGIN_COMMIT_CACHE}${ORIGIN_FS}${sha}${ORIGIN_FS}${line}"$'\n'
  else
    line="${hit%%$'\n'*}"
  fi

  ORIGIN_COMMIT_ISO="${line%%"$ORIGIN_FS"*}"
  ORIGIN_COMMIT_AGE="${line#*"$ORIGIN_FS"}"
  [ "$ORIGIN_COMMIT_AGE" = "$line" ] && ORIGIN_COMMIT_AGE=''
  return 0
}

worktree_list() {
  local format='table' arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      --json)
        format='json'
        shift
        ;;
      --porcelain)
        format='porcelain'
        shift
        ;;
      --no-forge)
        ORIGIN_NO_FORGE=1
        shift
        ;;
      -h | --help)
        cat >&2 <<'USAGE'
origin git-worktree list [--json | --porcelain] [--no-forge]   (aliases: gw list, gwl)
USAGE
        return 0
        ;;
      *) die "git-worktree list: unknown argument ${arg}" ;;
    esac
  done

  worktree_require

  local head_ref current root rows='' path sha branch flags use_forge=0 head_exists=0
  head_ref="$(repo_head_ref)"
  current="$(repo_root 2>/dev/null || printf '')"
  root="$(worktree_root)"

  # Once. The head ref is the same for every row, and asking per worktree cost
  # one `rev-parse` each.
  git rev-parse --verify --quiet "${head_ref}^{commit}" >/dev/null 2>&1 && head_exists=1

  if [ "${ORIGIN_NO_FORGE:-0}" != 1 ] && forge_available; then
    use_forge=1
    forge_pr_bulk_load
  fi

  while IFS="$ORIGIN_FS" read -r path sha branch flags; do
    [ -n "$path" ] || continue
    case "$flags" in *bare*) continue ;; esac

    local ahead=0 behind=0 counts dirty='clean' age='' committed='' pr='' pr_state='' pr_number=''
    if [ -n "$branch" ] && [ "$head_exists" = 1 ]; then
      counts="$(repo_ahead_behind "refs/heads/${branch}" "$head_ref")"
      ahead="${counts%% *}"
      behind="${counts##* }"
    fi
    worktree_is_dirty "$path" && dirty='dirty'
    worktree_commit_age "$sha"
    age="$ORIGIN_COMMIT_AGE"
    committed="$ORIGIN_COMMIT_ISO"
    if [ "$use_forge" = 1 ] && [ -n "$branch" ]; then
      pr="$(forge_pr_state_for "$branch")"
      pr_state="${pr%%$'\t'*}"
      pr_number="${pr##*$'\t'}"
    fi

    rows="${rows}$(printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s' \
      "$(worktree_display_name "$path" "$root")" "$path" "${branch:-(detached)}" \
      "$ahead" "$behind" "$dirty" "$pr_number" "$pr_state" \
      "$age" "$committed" "$flags")"$'\n'
  done <<EOF
$(worktree_records)
EOF

  case "$format" in
    json) worktree_list_json "$rows" "$current" ;;
    porcelain) printf '%s' "$rows" | tr '\037' '\t' ;;
    *) worktree_list_table "$rows" "$current" "${head_ref##*/}" ;;
  esac
}

worktree_list_json() {
  local rows="$1" current="$2" first=1
  local name path branch ahead behind dirty pr_number pr_state age committed flags
  printf '['
  while IFS="$ORIGIN_FS" read -r name path branch ahead behind dirty pr_number pr_state age committed flags; do
    [ -n "$path" ] || continue
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s}' \
      "$(json_field name "$name")" \
      "$(json_field path "$path")" \
      "$(json_field branch "$branch")" \
      "$(json_raw_field ahead "${ahead:-0}")" \
      "$(json_raw_field behind "${behind:-0}")" \
      "$(json_raw_field dirty "$(json_bool "$([ "$dirty" = dirty ] && printf 1 || printf 0)")")" \
      "$(json_raw_field current "$(json_bool "$([ "$path" = "$current" ] && printf 1 || printf 0)")")" \
      "$(json_raw_field pr "$(if [ -n "$pr_number" ]; then printf '{%s,%s}' "$(json_raw_field number "$pr_number")" "$(json_field state "$pr_state")"; else printf 'null'; fi)")" \
      "$(json_field lastCommit "$committed")" \
      "$(json_field age "$age")" \
      "$(json_field flags "$flags")"
  done <<EOF
$rows
EOF
  printf ']\n'
}

worktree_list_table() {
  local rows="$1" current="$2" head="$3"
  local name path branch ahead behind dirty pr_number pr_state age committed flags
  {
    printf 'NAME\tBRANCH\tVS %s\tSTATE\tPR\tAGE\tPATH\n' "$(printf '%s' "$head" | tr '[:lower:]' '[:upper:]')"
    while IFS="$ORIGIN_FS" read -r name path branch ahead behind dirty pr_number pr_state age committed flags; do
      [ -n "$path" ] || continue
      local marker='' pr='-'
      [ "$path" = "$current" ] && marker='* '
      [ -n "$pr_number" ] && pr="#${pr_number} $(printf '%s' "$pr_state" | tr '[:upper:]' '[:lower:]')"
      case "$flags" in *locked*) dirty="${dirty}, locked" ;; esac
      case "$flags" in *prunable*) dirty="${dirty}, prunable" ;; esac
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${marker}${name}" "$branch" "+${ahead:-0}/-${behind:-0}" "$dirty" "$pr" "${age:--}" \
        "$(worktree_pretty_path "$path")"
    done <<EOF
$rows
EOF
  } | tabulate
}

# --------------------------------------------------------------------------
# remove
# --------------------------------------------------------------------------

worktree_remove_usage() {
  cat >&2 <<'USAGE'
origin git-worktree remove <branch> | <path> [flags]   (aliases: gw remove, gwr)

  Removes a worktree whose branch is finished, and deletes the branch when git
  can prove its change is already in the head branch. The head branch itself is
  never deleted. A detached worktree goes when some ref already reaches the
  commit it sits on. Prints the command that puts back whatever went.

  --force             Remove the checkout of an unfinished branch, or of a
                      detached worktree no ref reaches. Keeps the branch, and
                      never touches uncommitted work.
  --delete-ignored    Delete the ignored files in the worktree too. Nothing
                      restores them; without this the removal stops and says
                      which they are.
  --no-forge          Do not ask the forge whether the pull request is done
  --dry-run           Say what would happen
  --yes               Do not ask about anything git could put back
USAGE
}

# The ignored files a worktree holds - `node_modules/`, `.env`, a build
# directory - collapsed the way git reports them.
#
# `git worktree remove` deletes the whole directory, these included, and
# `git status --porcelain` does not mention them, so without asking for them
# separately they go without ever being named.
worktree_ignored() {
  [ -d "$1" ] || return 0
  git -C "$1" status --porcelain --ignored=traditional 2>/dev/null |
    sed -n 's/^!! //p'
}

worktree_remove() {
  local target='' force=0 delete_ignored=0 arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      --force)
        force=1
        shift
        ;;
      --delete-ignored)
        delete_ignored=1
        shift
        ;;
      --no-forge)
        ORIGIN_NO_FORGE=1
        shift
        ;;
      -h | --help)
        worktree_remove_usage
        return 0
        ;;
      -*) die "git-worktree remove: unknown flag ${arg}" ;;
      *)
        target="$arg"
        shift
        ;;
    esac
  done

  worktree_require
  # Say which. Defaulting to the current branch cannot work: from inside its
  # own worktree that is the checkout you are standing in, and from the main
  # checkout it is the main worktree, and both are refused twenty lines down.
  [ -n "$target" ] ||
    die "git-worktree remove: which worktree? give a branch or a path - 'origin gwl' lists them"

  local path record branch at flags what
  path="$(worktree_path_of_branch "$target")"
  [ -n "$path" ] || path="$(repo_resolve_path "$target")"
  record="$(worktree_record_at "$path")"
  [ -n "$record" ] ||
    die "git-worktree remove: ${target} is not a worktree of this repository"
  branch="$(worktree_record_field "$record" 3)"
  at="$(worktree_record_field "$record" 2)"
  flags="$(worktree_record_field "$record" 4)"

  # An empty branch is a detached HEAD. That worktree holds a commit rather
  # than a branch, so every question below is asked about the commit instead.
  what="the worktree for ${branch}"
  [ -n "$branch" ] || what="the detached worktree at $(worktree_pretty_path "$path")"

  local main current
  main="$(repo_main_worktree)"
  current="$(repo_root 2>/dev/null || printf '')"
  [ "$path" = "$main" ] && die "git-worktree remove: that is the main worktree"
  [ "$path" = "$current" ] && die "git-worktree remove: that is the worktree you are standing in"

  case "$flags" in
    *locked*) die "git-worktree remove: ${what} is locked" ;;
  esac

  if [ -n "$branch" ]; then
    local stashes
    stashes="$(repo_stashes_for_branch "$branch")"
    [ "${stashes:-0}" -gt 0 ] &&
      die "git-worktree remove: ${branch} has ${stashes} stash $([ "$stashes" = 1 ] && printf 'entry' || printf 'entries')"
  fi

  repo_fetch
  local head_branch='' head_ref='' reason='' reached='' merged=0 finished=0
  if [ -n "$branch" ]; then
    head_branch="$(repo_head_branch)"
    head_ref="$(repo_head_ref_for "$head_branch")"
    if reason="$(merged_reason "$branch" "$head_ref")"; then
      merged=1
      finished=1
    fi
  else
    # A commit is finished when something else already reaches it. A ref that
    # does leaves nothing behind here; none at all makes this checkout the only
    # thing pointing at that commit.
    reached="$(git for-each-ref --contains "$at" --count=1 --format='%(refname)' 2>/dev/null || printf '')"
    if [ -n "$reached" ]; then
      finished=1
    fi
  fi

  # The sha this run can name: a branch's tip, or the commit a detached
  # worktree sits on.
  local sha='' commit=''
  if [ -n "$branch" ]; then
    sha="$(git rev-parse --short "refs/heads/${branch}" 2>/dev/null || printf '')"
    commit="$(git rev-parse --verify --quiet "refs/heads/${branch}" 2>/dev/null || printf '')"
  else
    sha="$(git rev-parse --short "$at" 2>/dev/null || printf '')"
  fi

  # The forge knows two things git here cannot: a pull request merged into a
  # branch this clone has not fetched, and one somebody closed without merging.
  # Either means the checkout has nothing left to do.
  #
  # Neither is evidence about the branch's commits, so neither deletes it. That
  # stays with `merged_reason`, which compares content and is the only thing
  # here that can prove nothing would be lost.
  local pr='' pr_state='' pr_number=''
  if [ -n "$branch" ] && [ "$finished" = 0 ] && [ "${ORIGIN_NO_FORGE:-0}" != 1 ] && forge_available; then
    forge_pr_bulk_load
    pr="$(forge_pr_state_for "$branch")"
    pr_state="${pr%%$'\t'*}"
    pr_number="${pr##*$'\t'}"
    case "$pr_state" in
      MERGED | CLOSED)
        finished=1
        note "$(forge_noun) #${pr_number} is $(printf '%s' "$pr_state" | tr '[:upper:]' '[:lower:]'); the branch itself stays"
        ;;
    esac
  fi

  # Uncommitted work is refused, and no flag changes that. The checkout is the
  # only place that work exists, so removing it is not a worktree operation -
  # it is deleting somebody's afternoon, with nothing to restore it from.
  if worktree_is_dirty "$path"; then
    say ''
    git -C "$path" status --short 2>/dev/null | indent_lines || true
    say ''
    say "Commit them, stash them, or remove ${path} yourself."
    die "git-worktree remove: ${branch} has uncommitted changes"
  fi

  local unpushed extra=''
  if [ -n "$branch" ]; then
    unpushed="$(merged_unpushed_count "$branch")"
    [ "${unpushed:-0}" -gt 0 ] && extra=" and has ${unpushed} commit(s) on no remote"
  fi
  if [ "$finished" = 0 ]; then
    if [ "$force" = 0 ]; then
      say ''
      if [ -n "$branch" ]; then
        say "${branch} is not merged into $(ref_name "$head_ref")${extra}."
        if repo_head_branch_misstated "$head_ref"; then
          say "git-worktree-plugin.headBranch names ${head_ref}, which is no branch here or on ${ORIGIN_REMOTE:-the remote}, so nothing reaches it. 'origin doctor' has the rest."
        fi
        die "git-worktree remove: refusing; pass --force to remove the checkout and keep the branch"
      fi
      say "no ref reaches ${sha}, so this checkout is the only thing pointing at that commit."
      die "git-worktree remove: refusing; keep it with 'git branch <name> ${sha}', or pass --force"
    fi
    if [ -n "$branch" ]; then
      warn "${branch} is not merged; removing the checkout and keeping the branch because --force"
    else
      warn "no ref reaches ${sha}; removing the checkout because --force"
    fi
  fi

  # --force removes a checkout. It never deletes a branch: it is what somebody
  # reaches for when a refusal is in the way, and that is the wrong moment to
  # do more than was asked.
  local delete_branch=0
  if [ "$merged" = 1 ] && [ "$force" = 0 ]; then
    delete_branch=1
  fi

  # A worktree can hold the head branch while the main checkout is elsewhere,
  # and a head branch the remote already has arrives here finished. The
  # checkout goes on that answer; the branch everything else is measured
  # against is not one this deletes.
  if [ "$delete_branch" = 1 ] && [ "$branch" = "$head_branch" ]; then
    delete_branch=0
  fi

  # b2, as an invariant rather than a courtesy: a branch whose sha this run
  # could not read is a branch it cannot tell anybody how to get back, so it
  # does not delete it.
  if [ "$delete_branch" = 1 ] && [ -z "$sha" ]; then
    warn "cannot read the sha of ${branch}; keeping the branch, because a deletion nobody can undo is not one this does"
    delete_branch=0
  fi

  # Everything that will not be there afterwards, named before the question.
  local ignored line ignored_count=0 losses=()
  ignored="$(worktree_ignored "$path")"
  [ -n "$ignored" ] && ignored_count="$(printf '%s\n' "$ignored" | grep -c . || true)"

  losses+=("the worktree at $(worktree_pretty_path "$path")")
  if [ "${ignored_count:-0}" -gt 0 ]; then
    losses+=("${ignored_count} ignored path(s) in it, which nothing tracks and nothing restores:")
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      losses+=("    ${line}")
    done <<EOF
$(printf '%s\n' "$ignored" | head -10)
EOF
    [ "$ignored_count" -gt 10 ] && losses+=("    ... and $((ignored_count - 10)) more")
  fi
  if [ "$delete_branch" = 1 ]; then
    losses+=("branch ${branch} (${sha}) — restore with: git branch ${branch} ${sha}")
  elif [ -z "$branch" ] && [ "$finished" = 1 ]; then
    losses+=("the commit ${sha} stays; ${reached} reaches it")
  elif [ -z "$branch" ]; then
    losses+=("the last ref to ${sha} — restore with: git worktree add --detach ${path} ${sha}")
  elif [ "$branch" = "$head_branch" ]; then
    losses+=("branch ${branch} stays; it is the head branch")
  else
    losses+=("branch ${branch} stays")
  fi
  losing "This will delete:" "${losses[@]}"

  # The ignored paths are the one thing here with no way back. --yes does not
  # answer for them.
  if [ "${ignored_count:-0}" -gt 0 ] && [ "$delete_ignored" = 0 ]; then
    confirm_unrecoverable \
      "Delete those ${ignored_count} ignored path(s) along with the worktree?" \
      --delete-ignored
  fi

  if [ -n "$branch" ]; then
    confirm "Remove ${what}?" \
      "git worktree remove ${path}" \
      "$([ "$delete_branch" = 1 ] && printf 'git branch -d %s' "$branch" || printf 'keep branch %s' "$branch")"
  else
    confirm "Remove ${what}?" "git worktree remove ${path}"
  fi

  # Nothing escalates to `git worktree remove --force`. Everything this plugin
  # can name has been checked; whatever git is still holding on to is something
  # nobody here has looked at, and the command that discards it is the user's
  # to type.
  git_run worktree remove "$path" || {
    say ''
    say "Look at ${path}. If it holds nothing you want:"
    say "  git worktree remove --force ${path}"
    die "git-worktree remove: git would not remove ${path}, and nothing here will override it"
  }
  worktree_prune_empty_parents "$path"

  if [ "$delete_branch" = 1 ]; then
    worktree_delete_branch "$branch" "$sha" "$reason" "$commit"
  elif [ -n "$branch" ]; then
    note "kept branch ${branch}"
  fi

  git_run worktree prune
  good "removed ${what}"
}

# Deletes a branch this run has proved merged, and says how to undo it.
#
# The sha is not decoration. It is the whole reason deleting a branch is
# allowed at all, so a call without one deletes nothing - and neither does one
# whose branch is no longer at it.
worktree_delete_branch() {
  local branch="$1" sha="$2" reason="$3" commit="${4-}" now
  [ -n "$sha" ] || {
    warn "not deleting ${branch}: nothing recorded the sha that would restore it"
    return 0
  }
  # `git branch -d` deletes a name, and takes whatever that name points at now.
  # The restore line names a commit. This holds the two together, and it is the
  # last thing between a branch read wrongly and a lost afternoon.
  #
  # The whole sha, passed in beside the short one, because `${sha}` is a name
  # to git before it is an object: a branch or tag actually called `a1b2c3d`
  # answers for it and the comparison would fail on a branch that never moved.
  now="$(git rev-parse --verify --quiet "refs/heads/${branch}" 2>/dev/null || printf '')"
  if [ -z "$commit" ] || [ -z "$now" ] || [ "$now" != "$commit" ]; then
    warn "not deleting ${branch}: it is no longer at ${sha}, which is the only commit the restore line offers"
    return 0
  fi
  if ! git_run branch -d "$branch" 2>/dev/null; then
    # `git branch -d` refuses a squash-merged branch: from where git stands it
    # is unmerged. The proof it is not is `reason`.
    ORIGIN_ALLOW_FORCE_DELETE=1
    git_run branch -D "$branch" 2>/dev/null || {
      ORIGIN_ALLOW_FORCE_DELETE=0
      warn "removed the worktree but could not delete ${branch}"
      return 0
    }
    ORIGIN_ALLOW_FORCE_DELETE=0
  fi
  say "deleted branch ${branch} (was ${sha}) — ${reason}"
  say "  restore: git branch ${branch} ${sha}"
}

# The directory a nested branch name leaves behind, never the root itself.
worktree_prune_empty_parents() {
  local root parent
  root="$(worktree_root)"
  parent="$(dirname "$1")"
  while [ "$parent" != "$root" ]; do
    case "$parent" in
      "$root"/*) ;;
      *) break ;;
    esac
    [ -d "$parent" ] || break
    [ -z "$(ls -A "$parent" 2>/dev/null)" ] || break
    origin_run rmdir "$parent" || break
    parent="$(dirname "$parent")"
  done
  return 0
}

# --------------------------------------------------------------------------
# move
# --------------------------------------------------------------------------

worktree_move_usage() {
  cat >&2 <<'USAGE'
origin git-worktree move <new-branch>   (aliases: gw move, gwm)

  Rename this worktree's branch and move its checkout so the two agree.
USAGE
}

# Renames the branch checked out here, and moves the checkout to match.
#
# Directory name equals branch name is the invariant every command here reads,
# so this is two git operations that have to happen together. `git branch -m`
# alone leaves a worktree whose directory says one thing and whose HEAD says
# another, which is the state `gwl` and `gwr` both misread; `git worktree move`
# alone renames nothing.
#
# Three pieces of tidying git will not do: the new parent has to exist before
# `git worktree move` will write into it, the old one is left behind empty, and
# neither is `git worktree move`'s business.
worktree_move() {
  local new='' arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      -h | --help)
        worktree_move_usage
        return 0
        ;;
      -*) die "git-worktree move: unknown argument ${arg}" ;;
      *)
        [ -z "$new" ] || die "git-worktree move: one branch name, not two - usage: origin gwm <new-branch>"
        new="$arg"
        shift
        ;;
    esac
  done

  [ -n "$new" ] || die "git-worktree move: which name? usage: origin gwm <new-branch>"
  git check-ref-format --branch "$new" >/dev/null 2>&1 ||
    die "git-worktree move: '${new}' is not a valid branch name"

  worktree_require

  local main src record branch flags dest state
  main="$(repo_main_worktree)"
  src="$(repo_root 2>/dev/null || printf '')"
  [ -n "$src" ] || die "git-worktree move: not inside a worktree of this repository"
  [ "$src" != "$main" ] ||
    die "git-worktree move: that is the main worktree; git cannot move it, and its directory is not named after a branch"

  record="$(worktree_record_at "$src")"
  [ -n "$record" ] || die "git-worktree move: ${src} is not a worktree of this repository"
  branch="$(worktree_record_field "$record" 3)"
  flags="$(worktree_record_field "$record" 4)"

  case "$flags" in
    *locked*)
      say "Unlock it first:"
      say "  git -C $(quote_args "$main") worktree unlock $(quote_args "$src")"
      die "git-worktree move: ${src} is locked"
      ;;
  esac
  [ -n "$branch" ] ||
    die "git-worktree move: ${src} has no branch checked out; there is nothing to rename"
  [ "$branch" != "$new" ] || die "git-worktree move: ${branch} is already called that"
  git show-ref --verify --quiet "refs/heads/${new}" &&
    die "git-worktree move: branch ${new} already exists"

  dest="$(worktree_path_for "$new")"
  state="$(worktree_dest_state "$dest")"
  case "$state" in
    free) ;;
    ours) die "git-worktree move: ${dest} is already a worktree of this repository" ;;
    blocked:*) die "git-worktree move: ${state#blocked:}" ;;
    *) die "git-worktree move: cannot tell what is at ${dest}" ;;
  esac

  say ''
  say "This will rename ${branch} to ${new}, and move its checkout:"
  say "  $(worktree_pretty_path "$src")"
  say "  $(worktree_pretty_path "$dest")"
  confirm "Rename ${branch} to ${new}?" \
    "git -C $(quote_args "$main") branch -m $(quote_args "$branch") $(quote_args "$new")" \
    "git -C $(quote_args "$main") worktree move $(quote_args "$src") $(quote_args "$dest")"

  # The branch first. `git worktree move` records the path it moved to, so
  # renaming afterwards would leave the two halves recoverable in the wrong
  # order if the move failed.
  git_run -C "$main" branch -m "$branch" "$new"

  origin_run mkdir -p "$(dirname "$dest")" || {
    warn "${branch} is now ${new}; its worktree is still at ${src}"
    die "git-worktree move: could not create $(dirname "$dest")"
  }

  if ! git_run -C "$main" worktree move "$src" "$dest"; then
    warn "${branch} is now ${new}; its worktree is still at ${src}"
    say "  finish it with: git -C $(quote_args "$main") worktree move $(quote_args "$src") $(quote_args "$dest")"
    die "git-worktree move: the move failed"
  fi

  worktree_prune_empty_parents "$src"

  # A subprocess cannot cd its parent, so the shell that called this is still
  # standing in a directory that no longer exists. The path on stdout is what a
  # shell function cd's to.
  good "${new} at $(worktree_pretty_path "$dest")"
  [ "$src" = "$(pwd -P 2>/dev/null || printf '')" ] &&
    note "you are standing in the old path; cd to the one printed"
  printf '%s\n' "$dest"
}

# --------------------------------------------------------------------------
# prune
# --------------------------------------------------------------------------

worktree_prune_usage() {
  cat >&2 <<'USAGE'
origin prune [flags]

  Say which worktrees are finished, and why, one line each. Removes nothing
  unless --yes.

  --branch <name>     Consider only that branch
  --no-fetch          Assess from what is already here, without fetching
  --delete-ignored    Let a worktree holding ignored files go
  --yes               Remove what it proposes
USAGE
}

# One assessment per worktree: verdict, branch, path, reason.
#
# The verdicts are `go`, `keep` and `unknown`, and the third is not the second
# with a softer word: "no upstream, so nothing says whether this was pushed" is
# a different fact from "this is not merged", and a sweep that prints them the
# same way invites somebody to act on the wrong one.
#
# Every refusal `git-worktree remove` makes is checked here, in its order.
# Proposing something that would then be refused is a bug in this, not a
# surprise at the confirmation.
worktree_prune_assess() {
  local only="$1" head_branch head_ref main current
  local record path sha branch flags reason unpushed ignored_count

  head_branch="$(repo_head_branch)"
  head_ref="$(repo_head_ref_for "$head_branch")"
  main="$(repo_main_worktree)"
  current="$(repo_root 2>/dev/null || printf '')"

  while IFS="$ORIGIN_FS" read -r path sha branch flags; do
    [ -n "$path" ] || continue
    case "$flags" in *bare*) continue ;; esac
    [ "$path" = "$main" ] && continue
    [ -n "$only" ] && [ "$branch" != "$only" ] && continue

    if [ "$path" = "$current" ]; then
      printf 'keep%s%s%s%s%syou are standing in it\n' \
        "$ORIGIN_FS" "${branch:-(detached)}" "$ORIGIN_FS" "$path" "$ORIGIN_FS"
      continue
    fi
    case "$flags" in
      *locked*)
        printf 'keep%s%s%s%s%sit is locked\n' \
          "$ORIGIN_FS" "${branch:-(detached)}" "$ORIGIN_FS" "$path" "$ORIGIN_FS"
        continue
        ;;
    esac
    if [ -n "$branch" ] && [ "$branch" = "$head_branch" ]; then
      printf 'keep%s%s%s%s%sit is the head branch\n' \
        "$ORIGIN_FS" "$branch" "$ORIGIN_FS" "$path" "$ORIGIN_FS"
      continue
    fi
    if worktree_is_dirty "$path"; then
      printf 'keep%s%s%s%s%sit has uncommitted changes\n' \
        "$ORIGIN_FS" "${branch:-(detached)}" "$ORIGIN_FS" "$path" "$ORIGIN_FS"
      continue
    fi

    if [ -z "$branch" ]; then
      # Detached: finished when some ref already reaches the commit, which is
      # the same question `git-worktree remove` asks of one.
      if [ -n "$(git for-each-ref --count=1 --contains "$sha" 2>/dev/null)" ]; then
        printf 'go%s(detached)%s%s%sits commit is reached by a ref\n' \
          "$ORIGIN_FS" "$ORIGIN_FS" "$path" "$ORIGIN_FS"
      else
        printf 'unknown%s(detached)%s%s%sno ref reaches %s\n' \
          "$ORIGIN_FS" "$ORIGIN_FS" "$path" "$ORIGIN_FS" "$sha"
      fi
      continue
    fi

    if ! reason="$(merged_reason "$branch" "$head_ref")"; then
      unpushed="$(merged_unpushed_count "$branch")"
      if [ -z "$(repo_upstream "$branch")" ]; then
        printf 'unknown%s%s%s%s%snot merged into %s, and no upstream says whether %s commit(s) were pushed\n' \
          "$ORIGIN_FS" "$branch" "$ORIGIN_FS" "$path" "$ORIGIN_FS" \
          "$(ref_name "$head_ref")" "${unpushed:-0}"
      else
        printf 'keep%s%s%s%s%snot merged into %s\n' \
          "$ORIGIN_FS" "$branch" "$ORIGIN_FS" "$path" "$ORIGIN_FS" "$(ref_name "$head_ref")"
      fi
      continue
    fi

    ignored_count="$(worktree_ignored "$path" | grep -c . || true)"
    if [ "${ignored_count:-0}" -gt 0 ] && [ "$ORIGIN_PRUNE_DELETE_IGNORED" = 0 ]; then
      printf 'keep%s%s%s%s%s%s, but holds %s ignored path(s); pass --delete-ignored\n' \
        "$ORIGIN_FS" "$branch" "$ORIGIN_FS" "$path" "$ORIGIN_FS" "$reason" "$ignored_count"
      continue
    fi

    printf 'go%s%s%s%s%s%s\n' "$ORIGIN_FS" "$branch" "$ORIGIN_FS" "$path" "$ORIGIN_FS" "$reason"
  done <<EOF
$(worktree_records)
EOF
  return 0
}

ORIGIN_PRUNE_DELETE_IGNORED=0

worktree_prune() {
  local only='' fetch=1 act=0 arg
  ORIGIN_PRUNE_DELETE_IGNORED=0
  while [ "$#" -gt 0 ]; do
    arg="$1"
    # Before parse_common_flag, which would take it. A flag meaning "do not
    # act" on a command that does not act is a no-op wearing the clothes of a
    # safety feature, and somebody will one day read it as the reason a sweep
    # was safe.
    case "$arg" in
      --dry-run)
        die "prune: there is no --dry-run; prune assesses and prints, and only --yes removes anything"
        ;;
    esac
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      --branch)
        require_value --branch "$@"
        only="$2"
        shift 2
        ;;
      --no-fetch)
        fetch=0
        shift
        ;;
      --delete-ignored)
        ORIGIN_PRUNE_DELETE_IGNORED=1
        shift
        ;;
      -h | --help)
        worktree_prune_usage
        return 0
        ;;
      *) die "prune: unknown argument ${arg}" ;;
    esac
  done

  [ "$ORIGIN_ASSUME_YES" = 1 ] && act=1
  worktree_require

  # The fetch is what the assessment rests on: `: gone]` and every
  # merged-ness answer below are read from remote-tracking refs, and a stale
  # one gives a confident wrong answer rather than an uncertain right one.
  if [ "$fetch" = 1 ]; then
    repo_fetch
  else
    note "assessing from what is already here; refs may be stale (--no-fetch)"
    # Each removal below is `git-worktree remove`, which fetches on its own
    # unless something already has. Without this, --no-fetch would suppress one
    # fetch and then perform one per worktree.
    ORIGIN_FETCHED=1
  fi

  # Git's own bookkeeping for worktrees whose directories somebody removed by
  # hand. Nothing else here calls it, and a stale entry is a record that
  # answers for a directory that is not there.
  git_run worktree prune

  local rows go_count=0 kept=0 unknown=0 verdict branch path reason failed=0
  rows="$(worktree_prune_assess "$only")"

  if [ -z "$rows" ]; then
    good "nothing to prune"
    return 0
  fi

  while IFS="$ORIGIN_FS" read -r verdict branch path reason; do
    [ -n "$verdict" ] || continue
    case "$verdict" in
      go) go_count=$((go_count + 1)) ;;
      keep) kept=$((kept + 1)) ;;
      unknown) unknown=$((unknown + 1)) ;;
    esac
  done <<EOF
$rows
EOF

  {
    printf 'VERDICT\tBRANCH\tWHY\tPATH\n'
    while IFS="$ORIGIN_FS" read -r verdict branch path reason; do
      [ -n "$verdict" ] || continue
      printf '%s\t%s\t%s\t%s\n' "$verdict" "$branch" "$reason" "$(worktree_pretty_path "$path")"
    done <<EOF
$rows
EOF
  } | tabulate

  say ''
  say "$(printf '%s to remove, %s kept, %s unclear' "$go_count" "$kept" "$unknown")"

  if [ "$go_count" = 0 ]; then
    return 0
  fi
  if [ "$act" = 0 ]; then
    say ''
    note "nothing removed; pass --yes to remove the ${go_count} above"
    return 0
  fi

  # The removal is `git-worktree remove` itself, one worktree at a time, so
  # every refusal it makes still applies and this cannot talk its way past one.
  # A subshell because those refusals are `die`: one worktree it will not take
  # is not a reason to abandon the rest of the sweep.
  while IFS="$ORIGIN_FS" read -r verdict branch path reason; do
    [ "$verdict" = go ] || continue
    if [ "$ORIGIN_PRUNE_DELETE_IGNORED" = 1 ]; then
      (worktree_remove "$path" --yes --delete-ignored) || failed=$((failed + 1))
    else
      (worktree_remove "$path" --yes) || failed=$((failed + 1))
    fi
  done <<EOF
$rows
EOF

  if [ "$failed" -gt 0 ]; then
    die "prune: $(printf '%s of %s' "$failed" "$go_count") could not be removed; each said why above"
  fi
  good "$(printf 'removed %s worktree(s)' "$go_count")"
}
