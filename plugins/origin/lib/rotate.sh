# shellcheck shell=bash
#
# The name the next branch takes when nobody supplies one.
#
# <branch>-YYYY-MM-DD_NNN, derived from the branch you are on. The stem has any
# suffix a previous run added taken off, so four branches in a day give four
# names rather than one name carrying four suffixes. Three digits, because a
# two-digit sequence beside -09-08 reads as another field of the date.

rotate_usage() {
  cat >&2 <<'USAGE'
origin rotate

  Print the name the next branch would take, and change nothing.

  <branch>-YYYY-MM-DD_NNN, from the branch you are on, at the first number
  free today. A name already taken here or on the remote is skipped, so two
  clones working the same day do not pick the same one.

  The head branch names nothing: a branch off it is new work rather than the
  next step, so from there a name is required.
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

# The next name, or a diagnosis of why there is not one.
rotate_next() {
  local branch head stem date candidate n=1
  branch="$(repo_current_branch)"
  [ -n "$branch" ] ||
    die "HEAD is detached, so there is no branch to name the next one after; pass a name"
  head="$(repo_head_branch 2>/dev/null || printf '')"
  [ "$branch" != "$head" ] ||
    die "${branch} is the head branch, and a branch off it is a new change rather than the next one; pass a name"

  stem="$(rotate_stem "$branch")"
  date="$(date +%Y-%m-%d)"
  while [ "$n" -lt 1000 ]; do
    candidate="$(printf '%s-%s_%03d' "$stem" "$date" "$n")"
    if ! rotate_name_taken "$candidate"; then
      printf '%s\n' "$candidate"
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
      *) die "rotate: unknown argument ${arg}" ;;
    esac
  done

  repo_require
  rotate_next
}
