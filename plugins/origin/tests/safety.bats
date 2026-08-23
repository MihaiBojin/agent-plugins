#!/usr/bin/env bats
#
# The rules that are enforced once, in lib/common.sh, rather than five times.
#
# These are the tests that matter most: everything else here is about being
# useful, and this is about the day somebody's work would otherwise be gone.

load helpers/repo

setup() {
  setup_repo
  # shellcheck source=../lib/common.sh
  . "${BATS_TEST_DIRNAME}/../lib/common.sh"
}

@test "git reset --hard is refused" {
  run git_guard reset --hard HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"never discards work"* ]]
}

@test "git clean -fdx is refused" {
  run git_guard clean -fdx
  [ "$status" -eq 1 ]
  [[ "$output" == *"never deletes untracked files"* ]]
}

@test "a bare --force push is refused, and names what to use instead" {
  run git_guard push --force origin main
  [ "$status" -eq 1 ]
  [[ "$output" == *"--force-with-lease --force-if-includes"* ]]
}

@test "--force-with-lease is not mistaken for --force" {
  run git_guard push --force-with-lease --force-if-includes origin main
  [ "$status" -eq 0 ]
}

@test "git branch -D is refused unless something has proved the branch merged" {
  run git_guard branch -D doomed
  [ "$status" -eq 1 ]
  [[ "$output" == *"explicit --force"* ]]

  ORIGIN_ALLOW_FORCE_DELETE=1
  run git_guard branch -D doomed
  [ "$status" -eq 0 ]
}

@test "every other spelling of a force delete is refused too" {
  # git accepts all of these and they all delete an unmerged branch.
  run git_guard branch --delete --force doomed
  [ "$status" -eq 1 ]
  run git_guard branch -d -f doomed
  [ "$status" -eq 1 ]
  run git_guard branch -df doomed
  [ "$status" -eq 1 ]
  run git_guard branch -fd doomed
  [ "$status" -eq 1 ]
  run git_guard branch --force --delete doomed
  [ "$status" -eq 1 ]
}

@test "a plain delete and a plain force are not a force delete" {
  run git_guard branch --delete finished
  [ "$status" -eq 0 ]
  run git_guard branch -d finished
  [ "$status" -eq 0 ]
  run git_guard branch --force wip main
  [ "$status" -eq 0 ]
}

@test "git worktree remove --force is refused, and nothing can grant it" {
  run git_guard worktree remove --force "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"left alone, not removed"* ]]

  # The variable that used to buy an exception is gone. Setting one by that
  # name, or any other, changes nothing.
  ORIGIN_ALLOW_WORKTREE_FORCE=1
  run git_guard worktree remove --force "$REPO"
  [ "$status" -eq 1 ]

  run git_guard worktree remove -f "$REPO"
  [ "$status" -eq 1 ]
}

@test "ordinary git is left alone" {
  run git_guard branch -d finished
  [ "$status" -eq 0 ]
  run git_guard reset --soft HEAD~1
  [ "$status" -eq 0 ]
  run git_guard clean -n
  [ "$status" -eq 0 ]
}

@test "confirm refuses rather than assuming consent when it cannot ask" {
  ORIGIN_ASSUME_YES=0
  run env ORIGIN_TTY_MISSING=1 bash -c "
    . '${BATS_TEST_DIRNAME}/../lib/common.sh'
    ORIGIN_ASSUME_YES=0
    confirm 'Do the thing?' 'rm -rf /' </dev/null
  " 2>/dev/null || true
  # Either it refused for want of a terminal, or it read EOF and aborted.
  [ "$status" -ne 0 ]
}

@test "confirm under --yes reads nothing at all" {
  ORIGIN_ASSUME_YES=1
  run confirm "Do the thing?" "git push"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a dry run runs nothing" {
  ORIGIN_DRY_RUN=1
  run origin_run touch "${ROOT}/should-not-exist"
  [ "$status" -eq 0 ]
  [ ! -e "${ROOT}/should-not-exist" ]
  [[ "$output" == *"would run:"* ]]
}

@test "--yes answers a recoverable question and not an unrecoverable one" {
  ORIGIN_ASSUME_YES=1
  run confirm "Delete a branch that prints its restore command?" "git branch -d x"
  [ "$status" -eq 0 ]

  run confirm_unrecoverable "Delete files nothing tracks?" --delete-ignored
  [ "$status" -eq 1 ]
  [[ "$output" == *"--yes does not answer that"* ]]
  [[ "$output" == *"--delete-ignored"* ]]
}

@test "what is being deleted is printed even with the commentary off" {
  ORIGIN_QUIET=1
  ORIGIN_ASSUME_YES=1
  run losing "This will delete:" "branch x (abc1234) — restore with: git branch x abc1234"
  [ "$status" -eq 0 ]
  [[ "$output" == *"This will delete:"* ]]
  [[ "$output" == *"git branch x abc1234"* ]]
}

@test "a flag that takes a value says which one was short" {
  run require_value --path
  [ "$status" -eq 1 ]
  [[ "$output" == *"--path needs a value"* ]]

  run require_value --path "${ROOT}/somewhere"
  [ "$status" -eq 0 ]
}
