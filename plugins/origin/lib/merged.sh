# shellcheck shell=bash
#
# Telling a finished branch from an unfinished one.
#
# `git branch --merged` answers for the merge that git can see. Most branches
# now end in a squash, which rewrites the commits into one, so git sees a
# branch whose commits appear nowhere in the head branch - the same shape as a
# branch nobody ever merged. Reaping on that reading loses work; refusing on it
# means never reaping anything.
#
# The standard resolution is to ask a different question: does the *change*
# this branch makes already exist in the head branch? Replay the branch's tree
# as a single commit on top of the merge base, and ask `git cherry` whether
# that patch is upstream. It answers about content rather than history, which
# is what a squash preserves.

# The synthetic commit is written into the object database, unreferenced, and
# collected by the next gc. Nothing points at it and nothing ever will.
MERGED_IDENTITY=(
  GIT_AUTHOR_NAME=origin
  GIT_AUTHOR_EMAIL=origin@localhost
  GIT_AUTHOR_DATE='@0 +0000'
  GIT_COMMITTER_NAME=origin
  GIT_COMMITTER_EMAIL=origin@localhost
  GIT_COMMITTER_DATE='@0 +0000'
)

# The plain case: every commit on the branch is already in the head branch.
merged_is_ancestor() {
  local branch="$1" head_ref="$2"
  git merge-base --is-ancestor "$branch" "$head_ref" 2>/dev/null
}

# The squash case.
merged_is_squashed() {
  local branch="$1" head_ref="$2" base tree head_tree synth verdict

  base="$(git merge-base "$head_ref" "$branch" 2>/dev/null || printf '')"
  [ -n "$base" ] || return 1
  tree="$(git rev-parse "${branch}^{tree}" 2>/dev/null || printf '')"
  [ -n "$tree" ] || return 1

  # A branch that leaves the head branch's tree exactly as it found it has
  # nothing left to contribute, whatever its history says.
  head_tree="$(git rev-parse "${head_ref}^{tree}" 2>/dev/null || printf '')"
  if [ -n "$head_tree" ] && [ "$tree" = "$head_tree" ]; then
    return 0
  fi

  synth="$(env "${MERGED_IDENTITY[@]}" git commit-tree "$tree" -p "$base" -m _ 2>/dev/null || printf '')"
  [ -n "$synth" ] || return 1

  # `-` means the patch is already upstream; `+` means it is not.
  verdict="$(git cherry "$head_ref" "$synth" 2>/dev/null || printf '')"
  case "$verdict" in
    '-'*) return 0 ;;
    *) return 1 ;;
  esac
}

# `merged`, `squash-merged`, or nothing and a non-zero status.
merged_reason() {
  local branch="$1" head_ref="$2"
  if merged_is_ancestor "$branch" "$head_ref"; then
    printf 'merged\n'
    return 0
  fi
  if merged_is_squashed "$branch" "$head_ref"; then
    printf 'squash-merged\n'
    return 0
  fi
  return 1
}

# Commits on the branch that its upstream has not got.
#
# A branch with unpushed work is not finished, whatever a merged pull request
# says about the part of it that was pushed.
merged_unpushed_count() {
  local branch="$1" upstream
  upstream="$(repo_upstream "$branch")"
  if [ -n "$upstream" ]; then
    git rev-list --count "${upstream}..${branch}" 2>/dev/null || printf '0\n'
    return 0
  fi
  # No upstream: count what no remote-tracking ref can reach. A branch never
  # pushed anywhere is entirely unpushed, not zero commits behind nothing.
  git rev-list --count "$branch" --not --remotes 2>/dev/null || printf '0\n'
}
