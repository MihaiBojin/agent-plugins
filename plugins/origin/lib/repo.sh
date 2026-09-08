# shellcheck shell=bash
#
# Facts about the repository in hand: where it is, which remote it belongs to,
# and which branch that remote calls default.

repo_require() {
  git rev-parse --git-dir >/dev/null 2>&1 ||
    die "not inside a git repository"
  # In this shell, so the answer is cached for every `$(repo_remote)` below and
  # an ambiguity stops the program instead of a subshell. No remote is fine.
  repo_remote_resolve || true
}

repo_root() {
  git rev-parse --show-toplevel
}

# Absolute. `git rev-parse --git-common-dir` answers relative to the working
# directory.
repo_common_dir() {
  git rev-parse --path-format=absolute --git-common-dir
}

ORIGIN_MAIN_WORKTREE=''

# The original clone, not a linked worktree. Empty for a bare repository.
#
# Cached, because it cannot move: `git worktree add` and `git worktree remove`
# both act on linked worktrees, and neither changes which one is the main
# checkout. `worktree_require` fills it, in a shell the answer outlives.
repo_main_worktree() {
  local line path='' bare=0
  if [ -n "$ORIGIN_MAIN_WORKTREE" ]; then
    printf '%s\n' "$ORIGIN_MAIN_WORKTREE"
    return 0
  fi
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      bare) bare=1 ;;
      '') break ;;
    esac
  done <<EOF
$(git worktree list --porcelain)
EOF
  # A bare repository has no main checkout, and nothing to cache.
  [ "$bare" = 1 ] && return 0
  ORIGIN_MAIN_WORKTREE="$path"
  printf '%s\n' "$path"
}

repo_name() {
  local main
  main="$(repo_main_worktree)"
  basename "${main:-$(repo_root)}"
}

# Empty when HEAD is detached.
#
# The prefix comes off here rather than from `--short`, which abbreviates to
# the shortest spelling git can still resolve: beside a tag called `feature`
# that is `heads/feature`, and every branch name this plugin passes on would
# carry it.
repo_current_branch() {
  local ref
  ref="$(git symbolic-ref --quiet HEAD 2>/dev/null || printf '')"
  printf '%s\n' "${ref#refs/heads/}"
}

repo_is_dirty() {
  [ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]
}

# The upstream of a branch, as `refs/remotes/<remote>/<branch>`.
#
# Full, because the answer is only ever handed back to git as a revision and
# `origin/main` is a name a tag can take. The branch itself stays short:
# `@{upstream}` is branch syntax, it refuses `refs/heads/<branch>@{upstream}`,
# and it already reads the branch rather than a tag of the same name.
repo_upstream() {
  git rev-parse --symbolic-full-name "${1}@{upstream}" 2>/dev/null || printf ''
}

# "<ahead> <behind>" against any ref.
repo_ahead_behind() {
  local counts
  counts="$(git rev-list --left-right --count "${1}...${2}" 2>/dev/null || printf '')"
  [ -n "$counts" ] || {
    printf '0 0\n'
    return 0
  }
  printf '%s\n' "$counts" | tr '\t' ' '
}

# --------------------------------------------------------------------------
# Which remote
# --------------------------------------------------------------------------

# The remote this repository belongs to, asked of the repository in decreasing
# order of how deliberate the answer is. A fork has `origin` pointing at the
# fork and `upstream` at the project the pull requests live on, so `origin` is
# a convention rather than an answer.
#
# `remote.pushDefault` is not asked. It names where commits go, not where they
# come from, and the two differ in exactly the case that makes this question
# worth asking: a fork you push to, an upstream you branch from. Reading it here
# would resolve the base to the fork.
#
# Prints the remote, or nothing with status 1 (there is none) or 2 (there are
# several and nothing says which).
repo_remote_compute() {
  local candidate branch count

  candidate="$(git config --get checkout.defaultRemote 2>/dev/null || printf '')"
  if [ -n "$candidate" ] && git remote get-url "$candidate" >/dev/null 2>&1; then
    printf '%s\n' "$candidate"
    return 0
  fi

  branch="$(repo_current_branch)"
  if [ -n "$branch" ]; then
    candidate="$(git config --get "branch.${branch}.remote" 2>/dev/null || printf '')"
    if [ -n "$candidate" ] && git remote get-url "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  count="$(git remote | grep -c . || true)"
  case "${count:-0}" in
    0) return 1 ;;
    1)
      git remote
      return 0
      ;;
    *) return 2 ;;
  esac
}

ORIGIN_REMOTE=''

# Resolve once, in the caller's own shell.
#
# `repo_remote` is read from inside `$(…)` all over this plugin, and a subshell
# takes both the cached answer and any `die` with it when it exits — so an
# ambiguity reported there would be swallowed by the caller's `|| printf ''`
# and the command would carry on with no remote and no explanation. This runs
# from `repo_require`, where it can still stop the program.
repo_remote_resolve() {
  local status=0
  [ -n "$ORIGIN_REMOTE" ] && return 0
  ORIGIN_REMOTE="$(repo_remote_compute)" || status=$?
  case "$status" in
    0) return 0 ;;
    2)
      say 'This repository has several remotes and nothing says which one it belongs to:'
      git remote -v | awk '$3 == "(fetch)" { printf "  %s\t%s\n", $1, $2 }' | tabulate
      die "say which with: git config checkout.defaultRemote <name>"
      ;;
    *)
      ORIGIN_REMOTE=''
      return 1
      ;;
  esac
}

repo_remote() {
  [ -n "$ORIGIN_REMOTE" ] || repo_remote_resolve || return 1
  printf '%s\n' "$ORIGIN_REMOTE"
}

repo_has_remote() {
  repo_remote >/dev/null 2>&1
}

# The URL git will use, after any `insteadOf` rewrite.
repo_remote_url() {
  local remote
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$remote" ] || {
    printf ''
    return 0
  }
  git remote get-url "$remote" 2>/dev/null || printf ''
}

# The URL as written in config, before any rewrite.
repo_remote_url_raw() {
  local remote
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$remote" ] || {
    printf ''
    return 0
  }
  git config --get "remote.${remote}.url" 2>/dev/null || printf ''
}

# --------------------------------------------------------------------------
# Which branch is the default
# --------------------------------------------------------------------------

# `refs/remotes/<remote>/HEAD` is what the server advertised at clone time and
# is the only answer that tells `master` from `main` without guessing.
#
# Reading it is all this does. When it is missing the server is asked with
# `ls-remote`, which answers the same question without writing the ref:
# `git remote set-head --auto` would record it, and a command that reports on a
# repository - `doctor`, or anything under --dry-run - must not change one.
# `ls-remote` writes nothing, so it runs under --dry-run as well, and a dry run
# names the same branch as the run it describes.
repo_head_branch() {
  local remote head candidate
  remote="$(repo_remote 2>/dev/null || printf '')"
  if [ -n "$remote" ]; then
    head="$(git symbolic-ref --quiet "refs/remotes/${remote}/HEAD" 2>/dev/null || printf '')"
    # Both prefixes, because the ref is written by hand often enough to point
    # at `refs/heads/<head>` rather than at this remote's copy of it.
    head="${head#"refs/remotes/${remote}/"}"
    head="${head#refs/heads/}"
    if [ -z "$head" ]; then
      head="$(git ls-remote --symref "$remote" HEAD 2>/dev/null |
        awk '$1 == "ref:" { sub(/^refs\/heads\//, "", $2); print $2; exit }')"
    fi
    if [ -n "$head" ]; then
      printf '%s\n' "$head"
      return 0
    fi
  fi

  head=''
  for candidate in main master trunk; do
    if [ -n "$remote" ] && git show-ref --verify --quiet "refs/remotes/${remote}/${candidate}"; then
      [ -n "$head" ] && head='?' && break
      head="$candidate"
    elif [ -z "$remote" ] && git show-ref --verify --quiet "refs/heads/${candidate}"; then
      [ -n "$head" ] && head='?' && break
      head="$candidate"
    fi
  done

  case "$head" in
    '' | '?')
      die "cannot tell which branch is the default${remote:+; record it with: git remote set-head ${remote} --auto}"
      ;;
  esac
  printf '%s\n' "$head"
}

# The head branch as a full ref: `refs/remotes/<remote>/<head>` when there is a
# remote, `refs/heads/<head>` when there is not.
#
# Full, so git resolves it to this ref and to nothing else. Git prefers a tag
# over everything below it, so a repository holding a tag called `origin/main`
# would answer every question about the head branch with that tag - including
# the question of whether a branch is finished and safe to delete.
#
# `ref_name` puts it back into the form a person writes.
repo_head_ref() {
  repo_head_ref_for "$(repo_head_branch)"
}

# The same, for a head branch already in hand.
#
# A caller that needs both the branch and the ref asks once and names the
# second from the first: `repo_head_branch` is not cached, so asking twice can
# mean two `ls-remote` round trips and two answers that a default branch
# renamed in between would make disagree.
repo_head_ref_for() {
  local head="$1" remote
  remote="$(repo_remote 2>/dev/null || printf '')"
  if [ -n "$remote" ] && git show-ref --verify --quiet "refs/remotes/${remote}/${head}"; then
    printf 'refs/remotes/%s/%s\n' "$remote" "$head"
  elif git show-ref --verify --quiet "refs/heads/${head}"; then
    printf 'refs/heads/%s\n' "$head"
  else
    # A name that is neither a branch here nor a branch on the remote is
    # something this does not recognise, and it goes back exactly as it came
    # for git to resolve as it always did. Prefixing it would produce
    # `refs/heads/<name>`, which resolves to nothing, and turn a repository
    # that worked into one where every command fails.
    printf '%s\n' "$head"
  fi
}

# A ref as a person writes it: `refs/remotes/origin/main` is `origin/main`,
# `refs/heads/feature` is `feature`.
#
# For prose. The commands this plugin prints keep the full ref, because those
# are what it runs and pasting one has to do the same thing.
ref_name() {
  case "${1-}" in
    refs/heads/*) printf '%s\n' "${1#refs/heads/}" ;;
    refs/remotes/*) printf '%s\n' "${1#refs/remotes/}" ;;
    refs/tags/*) printf '%s\n' "${1#refs/tags/}" ;;
    *) printf '%s\n' "${1-}" ;;
  esac
}

# --------------------------------------------------------------------------

ORIGIN_FETCHED=0

# Through `git_run`, because `--prune` deletes remote-tracking refs and a dry
# run changes nothing - not even a ref nobody looks at.
repo_fetch() {
  local remote
  [ "$ORIGIN_FETCHED" = 1 ] && return 0
  ORIGIN_FETCHED=1
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$remote" ] || return 0
  [ "$ORIGIN_DRY_RUN" = 1 ] || note "Fetching ${remote}"
  git_run fetch "$remote" --prune --quiet ||
    warn "could not fetch ${remote}; working from what is already here"
}

# Stash entries recorded against a branch. git writes "WIP on <branch>:" for a
# plain stash and "On <branch>:" for one with a message.
repo_stashes_for_branch() {
  git log -g refs/stash --format='%gs' 2>/dev/null |
    grep -c -i -F "on ${1}:" || true
}

repo_config_bool() {
  case "$(git config --get "$1" 2>/dev/null || printf '%s' "${2-}")" in
    true | yes | on | 1) return 0 ;;
    *) return 1 ;;
  esac
}

# shellcheck disable=SC2088  # the tilde is the pattern, not one to expand
expand_tilde() {
  case "${1-}" in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s\n' "${HOME}/${1#\~/}" ;;
    *) printf '%s\n' "${1-}" ;;
  esac
}

# A path in the form git prints: absolute, with symlinks resolved. On macOS
# $TMPDIR is a symlink, so a path a user typed and the same path git printed
# compare unequal until both have been through this.
repo_resolve_path() {
  local path tail=''
  path="$(expand_tilde "$1")"
  case "$path" in
    /*) ;;
    *) path="${PWD}/${path}" ;;
  esac
  while [ ! -d "$path" ]; do
    case "$path" in
      / | //) break ;;
    esac
    tail="$(basename "$path")${tail:+/}${tail}"
    path="$(dirname "$path")"
  done
  path="$(cd "$path" 2>/dev/null && pwd -P)" || {
    printf '%s\n' "$1"
    return 0
  }
  if [ -n "$tail" ]; then
    printf '%s/%s\n' "${path%/}" "$tail"
  else
    printf '%s\n' "$path"
  fi
}
