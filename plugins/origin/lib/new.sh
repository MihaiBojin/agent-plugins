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
origin new-branch <name> [flags]

  Fetch, then branch off the head branch and check it out.

  The name is required. `origin rotate` names and creates the next branch in
  a chain when you do not want to choose one.

  The base is the head branch as the remote has it, so the branch starts on
  top of the server's copy rather than on top of a stale local one. Nothing
  tracks the head branch: a branch that did would take it as its upstream, and
  `git push` would target it.

  --dry-run    Say what would happen
  --yes        Do not ask
USAGE
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
      -*) die "new-branch: unknown argument ${arg}" ;;
      *)
        [ -z "$name" ] || die "new-branch takes one name; ${name} and ${arg} are two"
        name="$1"
        shift
        ;;
    esac
  done

  repo_require

  [ -n "$name" ] ||
    die "new-branch: which name? 'origin rotate' takes the next one after this branch"

  new_start "$name"
}

# Fetch, then branch `$1` off the head branch and check it out.
new_start() {
  local name="$1"

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
