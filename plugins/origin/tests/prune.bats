#!/usr/bin/env bats
#
# `origin prune`: an assessment first, and an action only when asked.
#
# The verdicts are the contract. A port of this command has to reproduce what
# it prints, in what order, and how it says "I could not tell" - so these
# assert on the streams and the exit code rather than only on what is left on
# disk.

load helpers/repo

setup() {
  setup_repo
}

# A branch whose work has landed on main, with a worktree still sitting there.
finished_worktree() {
  origin_cli gwa "$1"
  [ "$status" -eq 0 ]
  (
    cd "${WORKTREES}/${1}/proj" || exit 1
    commit_file "${1}.txt" done "Work on ${1}"
  )
  squash_merge_branch "$1"
}

@test "it assesses and removes nothing" {
  finished_worktree done-one

  origin_cli prune
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"done-one"* ]]
  [[ "$stderr" == *"squash-merged"* ]]
  [[ "$stderr" == *"pass --yes"* ]]
  [ -d "${WORKTREES}/done-one/proj" ]
}

@test "--yes removes what it proposed" {
  finished_worktree done-one

  origin_cli prune --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/done-one/proj" ]
  run git show-ref --verify --quiet refs/heads/done-one
  [ "$status" -ne 0 ]
}

@test "unfinished work is kept, and says why" {
  origin_cli gwa feature
  (
    cd "${WORKTREES}/feature/proj" || exit 1
    commit_file work.txt yes "The work"
  )
  git push -q origin feature
  git branch --set-upstream-to=origin/feature feature 2>/dev/null || true

  origin_cli prune --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"keep"* ]]
  [[ "$stderr" == *"not merged into"* ]]
  [ -d "${WORKTREES}/feature/proj" ]
}

@test "a branch with no upstream is unclear rather than kept" {
  origin_cli gwa feature
  (
    cd "${WORKTREES}/feature/proj" || exit 1
    commit_file work.txt yes "The work"
  )

  origin_cli prune
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"unknown"* ]]
  [[ "$stderr" == *"no upstream"* ]]
  [[ "$stderr" == *"unclear"* ]]
}

@test "uncommitted work is kept, whatever else it is" {
  finished_worktree done-one
  printf 'scratch\n' >"${WORKTREES}/done-one/proj/untracked.txt"
  git -C "${WORKTREES}/done-one/proj" add untracked.txt

  origin_cli prune --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"uncommitted changes"* ]]
  [ -d "${WORKTREES}/done-one/proj" ]
}

@test "the head branch is never proposed" {
  origin_cli gwa main-elsewhere
  git -C "${WORKTREES}/main-elsewhere/proj" checkout -q main 2>/dev/null || skip "cannot check main out twice"

  origin_cli prune
  [[ "$stderr" != *"go"$'\t'"main"* ]]
}

@test "the worktree you are standing in is kept" {
  finished_worktree done-one
  cd "${WORKTREES}/done-one/proj"

  origin_cli prune --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"standing in it"* ]]
  [ -d "${WORKTREES}/done-one/proj" ]
}

@test "ignored files hold a finished worktree back until named" {
  # The ignore rule has to predate the worktree, or the checkout there does not
  # have it and the file is untracked rather than ignored.
  printf '.env\n' >.gitignore
  git add .gitignore
  git commit -qm "Ignore .env"
  git push -q origin main
  finished_worktree done-one
  printf 'SECRET=hunter2\n' >"${WORKTREES}/done-one/proj/.env"

  origin_cli prune --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"--delete-ignored"* ]]
  [ -d "${WORKTREES}/done-one/proj" ]
  [ -f "${WORKTREES}/done-one/proj/.env" ]
}

@test "--delete-ignored lets it go, and the ignored file goes with it" {
  printf '.env\n' >.gitignore
  git add .gitignore
  git commit -qm "Ignore .env"
  git push -q origin main
  finished_worktree done-one
  printf 'SECRET=hunter2\n' >"${WORKTREES}/done-one/proj/.env"

  origin_cli prune --yes --delete-ignored
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/done-one/proj" ]
}

@test "--branch considers only that one" {
  finished_worktree done-one
  finished_worktree done-two

  origin_cli prune --branch done-one
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"done-one"* ]]
  [[ "$stderr" != *"done-two"* ]]
}

@test "--no-fetch says the answer may be stale" {
  finished_worktree done-one

  origin_cli prune --no-fetch
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"may be stale"* ]]
}

@test "there is no --dry-run, and saying so is the point" {
  origin_cli prune --dry-run
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"there is no --dry-run"* ]]
}

@test "nothing to prune says so and exits 0" {
  origin_cli prune
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"nothing to prune"* ]]
}

# The invariant. `prune` proposing something `git-worktree remove` would then
# refuse is a bug in `prune`, so every `go` is handed to `gwr` and has to be
# taken.
@test "everything it proposes, git-worktree remove accepts" {
  finished_worktree done-one
  finished_worktree done-two
  origin_cli gwa unfinished
  (
    cd "${WORKTREES}/unfinished/proj" || exit 1
    commit_file work.txt yes "The work"
  )

  origin_cli prune
  [ "$status" -eq 0 ]
  local proposed
  proposed="$(printf '%s\n' "$stderr" | awk '$1 == "go" { print $2 }')"
  [ -n "$proposed" ]

  local branch
  for branch in $proposed; do
    origin_cli gwr "$branch" --yes
    [ "$status" -eq 0 ]
  done
}
