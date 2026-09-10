#!/usr/bin/env bats
#
# The name the next branch takes, and the two cases where there is not one.

load helpers/repo

setup() {
  setup_repo
}

@test "rotate: names the next branch after the one checked out" {
  origin_cli new-branch feature --yes
  origin_cli rotate
  [ "$status" -eq 0 ]
  [[ "$output" == "feature-$(date +%Y-%m-%d)_001" ]]
}

@test "rotate: changes nothing, so twice gives the same answer" {
  origin_cli new-branch feature --yes
  origin_cli rotate
  local first="$output"
  origin_cli rotate
  [ "$output" = "$first" ]
  run git show-ref --verify --quiet "refs/heads/${first}"
  [ "$status" -ne 0 ]
}

@test "rotate: skips a name that is already taken" {
  origin_cli new-branch feature --yes
  git branch "feature-$(date +%Y-%m-%d)_001"
  origin_cli rotate
  [[ "$output" == "feature-$(date +%Y-%m-%d)_002" ]]
}

@test "rotate: a branch carrying a suffix keeps one rather than gaining a second" {
  git checkout -q -b "feature-2020-01-01_001"
  origin_cli rotate
  [[ "$output" == "feature-$(date +%Y-%m-%d)_001" ]]
}

@test "rotate: the head branch names nothing" {
  origin_cli rotate
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"head branch"* ]]
}

@test "rotate: a detached HEAD has no branch to derive from" {
  git checkout -q --detach HEAD
  origin_cli rotate
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"detached"* ]]
}

@test "new-branch with no name takes the name rotate gives" {
  origin_cli new-branch feature --yes
  origin_cli rotate
  local expected="$output"
  origin_cli new-branch --yes
  [ "$status" -eq 0 ]
  run git rev-parse --abbrev-ref HEAD
  [ "$output" = "$expected" ]
}

@test "new: the old spelling names the new one" {
  origin_cli new feature --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"origin new-branch"* ]]
}
