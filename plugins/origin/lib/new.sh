# shellcheck shell=bash
#
# Starting a branch, off a head branch that was fetched a moment ago.
#
# The base is <remote>/<head> as it stands after the fetch, not the local copy
# of it, so a branch created here is already on top of what the server has and
# nothing has to be rebased afterwards.
#
# The same job as the `gnb` shell function, which is where this shape comes
# from. Duplicated rather than shared: a shell function is not reachable from
# an agent, and this file is.

new_usage() {
  cat >&2 <<'USAGE'
origin new [<name>] [flags]

  Fetch, then branch off the head branch and check it out.

  With no name, this branch names the next one: <branch>-YYYY-MM-DD_NNN, at
  the first number free today. A branch already carrying that suffix keeps one
  suffix rather than gaining a second. The head branch does not name anything,
  so from there a name is required.

  The base is the head branch as the remote has it, so the branch starts on
  top of the server's copy rather than on top of a stale local one. Nothing
  tracks the head branch: a branch that did would take it as its upstream, and
  `git push` would target it.

  --dry-run    Say what would happen
  --yes        Do not ask
USAGE
}

# <branch>-YYYY-MM-DD_NNN, from the branch this one continues.
#
# The stem has any suffix a previous run added taken off, so four branches in a
# day give four names rather than one name with four suffixes on it. Three
# digits, so the sequence cannot be read as another field of the date the way a
# two-digit one beside -09-08 can.
new_stem() {
  printf '%s\n' "$1" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{3}$//'
}

# Is this name spoken for, here or on the remote?
new_name_taken() {
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

# The name a nameless run gets, in the caller's own shell so `die` still stops
# the program: a `die` inside `$(…)` exits the subshell and lets the command
# carry on with an empty name.
new_generated_name() {
  local branch head stem date candidate n=1
  branch="$(repo_current_branch)"
  [ -n "$branch" ] ||
    die "HEAD is detached, so there is no branch to name the next one after; pass a name"
  head="$(repo_head_branch 2>/dev/null || printf '')"
  [ "$branch" != "$head" ] ||
    die "${branch} is the head branch, and a branch off it is a new change rather than the next one; pass a name"

  stem="$(new_stem "$branch")"
  date="$(date +%Y-%m-%d)"
  while [ "$n" -lt 1000 ]; do
    candidate="$(printf '%s-%s_%03d' "$stem" "$date" "$n")"
    if ! new_name_taken "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    n=$((n + 1))
  done
  die "every name derived from ${branch} is taken today; pass a name"
}

new_main() {
  local name='' arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      -h | --help)
        new_usage
        return 0
        ;;
      -*) die "new: unknown argument ${arg}" ;;
      *)
        [ -z "$name" ] || die "new takes one name; ${name} and ${arg} are two"
        name="$1"
        shift
        ;;
    esac
  done

  repo_require

  [ -n "$name" ] || name="$(new_generated_name)"

  git check-ref-format --branch "$name" >/dev/null 2>&1 ||
    die "${name} is not a valid branch name"
  ! git show-ref --verify --quiet "refs/heads/${name}" ||
    die "${name} is already a branch; git switch ${name} checks it out"

  repo_fetch

  local head head_ref
  head="$(repo_head_branch)"
  head_ref="$(repo_head_ref_for "$head")"
  git rev-parse --verify --quiet "${head_ref}^{commit}" >/dev/null ||
    die "there is no $(ref_name "$head_ref") to branch from"

  # A branch created off the remote's copy would otherwise take the head branch
  # as its upstream, and `git pull` would merge it back in.
  confirm "Start ${name} from $(ref_name "$head_ref")?" \
    "git switch --create ${name} --no-track ${head_ref}"

  git_run switch --create "$name" --no-track "$head_ref" ||
    die "could not create ${name}"

  local at
  at="$(git rev-parse --short "$head_ref" 2>/dev/null || printf '')"
  good "on ${name}, from $(ref_name "$head_ref")${at:+ at ${at}}"
}
