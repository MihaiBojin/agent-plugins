# shellcheck shell=bash
#
# The next branch in a chain, named after the one you are on.
#
# <branch>-YYYY-MM-DD_NNN. The stem has any suffix a previous run added taken
# off, so four branches in a day give four names rather than one name carrying
# four suffixes. Three digits, because a two-digit sequence beside -09-08 reads
# as another field of the date.
#
# On the head branch there is no chain to continue, so it brings the head branch
# up to date instead.

rotate_usage() {
  cat >&2 <<'USAGE'
origin rotate [flags]

  Start the next branch in this chain, named after the one you are on:
  <branch>-YYYY-MM-DD_NNN, at the first number free today. A name already
  taken here or on the remote is skipped, so two clones working the same day
  do not choose the same one. The base is the head branch as the remote has
  it, so the new branch starts on top of the server's copy.

  On the head branch there is no chain to continue, so it fast-forwards the
  head branch to the remote instead and says so.

  --dry-run    Say what would happen
  --yes        Do not ask
USAGE
}

# The branch name with any previous rotation suffix removed.
rotate_stem() {
  printf '%s\n' "$1" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{3}$//'
}

# Is this name spoken for, here or on the remote?
rotate_name_taken() {
  local name="$1" remote
  if git show-ref --verify --quiet "refs/heads/${name}"; then
    return 0
  fi
  remote="$(repo_remote 2>/dev/null || printf '')"
  if [ -n "$remote" ] && git show-ref --verify --quiet "refs/remotes/${remote}/${name}"; then
    return 0
  fi
  return 1
}

# The next name after `$1`, into a variable rather than down a pipe.
#
# A `die` inside `$(…)` exits the subshell and nothing else, so a refusal
# written that way would print its message and let the command carry on with an
# empty name. This runs in the caller's own shell, where `die` still stops the
# program.
ROTATE_NAME=''
rotate_next() {
  local branch="$1" stem date candidate n=1
  stem="$(rotate_stem "$branch")"
  date="$(date +%Y-%m-%d)"
  while [ "$n" -lt 1000 ]; do
    candidate="$(printf '%s-%s_%03d' "$stem" "$date" "$n")"
    if ! rotate_name_taken "$candidate"; then
      ROTATE_NAME="$candidate"
      return 0
    fi
    n=$((n + 1))
  done
  die "every name derived from ${branch} is taken today; pass a name"
}

rotate_main() {
  local arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      -h | --help)
        rotate_usage
        return 0
        ;;
      *) die "rotate: takes no arguments; 'origin new-branch ${arg}' is how you choose a name" ;;
    esac
  done

  repo_require

  local branch head head_ref
  branch="$(repo_current_branch)"
  [ -n "$branch" ] ||
    die "HEAD is detached, so there is no branch to name the next one after; 'origin new-branch <name>' names one"

  repo_fetch
  head="$(repo_head_branch)"
  head_ref="$(repo_head_ref_for "$head")"
  git rev-parse --verify --quiet "${head_ref}^{commit}" >/dev/null ||
    die "there is no $(ref_name "$head_ref") to branch from"

  # On the head branch there is nothing to continue, and the useful move is the
  # one `sync` already makes: a fast-forward, which refuses rather than
  # rewriting when this copy is ahead.
  if [ "$branch" = "$head" ]; then
    sync_fast_forward "$head" "$head_ref" 0
    return 0
  fi

  rotate_next "$branch"
  new_start "$ROTATE_NAME"
}
