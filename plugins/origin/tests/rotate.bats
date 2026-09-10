#!/usr/bin/env bats
#
# The next branch in a chain: the name it takes, where it starts, and what
# happens on the head branch where there is no chain to continue.

load helpers/repo

setup() {
  setup_repo
}

@test "rotate: creates the next branch after the one checked out" {
  origin_cli new-branch feature --yes
  origin_cli rotate --yes
  [ "$status" -eq 0 ]
  run git rev-parse --abbrev-ref HEAD
  [ "$output" = "feature-$(date +%Y-%m-%d)_001" ]
}

@test "rotate: starts from the head branch as the remote has it" {
  origin_cli new-branch feature --yes
  commit_file work.txt mine
  origin_cli rotate --yes
  run git rev-parse HEAD
  local here="$output"
  run git rev-parse refs/remotes/origin/main
  [ "$output" = "$here" ]
}

@test "rotate: does not track the head branch" {
  origin_cli new-branch feature --yes
  origin_cli rotate --yes
  run git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
  [ "$status" -ne 0 ]
}

@test "rotate: twice gives the next number" {
  origin_cli new-branch feature --yes
  origin_cli rotate --yes
  origin_cli rotate --yes
  [ "$status" -eq 0 ]
  run git rev-parse --abbrev-ref HEAD
  [ "$output" = "feature-$(date +%Y-%m-%d)_002" ]
}

@test "rotate: skips a name the remote holds" {
  origin_cli new-branch feature --yes
  git push -q origin "HEAD:refs/heads/feature-$(date +%Y-%m-%d)_001"
  git fetch -q origin
  origin_cli rotate --yes
  run git rev-parse --abbrev-ref HEAD
  [ "$output" = "feature-$(date +%Y-%m-%d)_002" ]
}

@test "rotate: a branch carrying a suffix keeps one rather than gaining a second" {
  git checkout -q -b "feature-2020-01-01_001"
  origin_cli rotate --yes
  run git rev-parse --abbrev-ref HEAD
  [ "$output" = "feature-$(date +%Y-%m-%d)_001" ]
}

@test "rotate: the head branch has no chain, so it fast-forwards" {
  upstream_moves
  origin_cli rotate --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"main is at origin/main"* ]]
  run git log --oneline -1 --format=%s main
  [ "$output" = "A commit from somewhere else" ]
}

@test "rotate: local commits on the head branch are shown, not discarded" {
  commit_file accident.txt yes "A commit that should not be here"
  upstream_moves
  origin_cli rotate --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"A commit that should not be here"* ]]
  [[ "$stderr" == *"would lose them"* ]]
  run git log --oneline -1 --format=%s main
  [ "$output" = "A commit that should not be here" ]
}

@test "rotate: a detached HEAD has no branch to derive from" {
  git checkout -q --detach HEAD
  origin_cli rotate --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"detached"* ]]
}

@test "rotate: a name argument names new-branch instead" {
  origin_cli new-branch feature --yes
  origin_cli rotate other --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"origin new-branch other"* ]]
}

@test "new: the old spelling names the new one" {
  origin_cli new feature --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"origin new-branch"* ]]
}
