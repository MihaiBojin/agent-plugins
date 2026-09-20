#!/usr/bin/env bats
#
# Deleting finished branches, and the difference between one the forge can
# give back and one only this clone has ever held.

load helpers/repo

setup() {
  setup_repo
  stub_forge https://github.com/owner/repo.git
  pr_list '[]'
}

pr_list() {
  printf '%s\n' "$1" >"${ORIGIN_STUB_DIR}/pr-list.json"
}

# A branch that was pushed, then squashed onto main. Leaves the checkout on
# main, with the branch and its remote-tracking ref both still here.
finished_branch() {
  local name="$1"
  git checkout -qb "$name"
  commit_file "${name}.txt" one "Work on ${name}"
  git push -q -u origin "$name"
  squash_merge_branch "$name"
}

@test "a branch with a merged pull request goes, here and on the remote" {
  finished_branch feature
  pr_list '[ { "number": 7, "headRefName": "feature", "state": "MERGED" } ]'

  origin_cli prune --yes
  [ "$status" -eq 0 ]

  run git show-ref --verify --quiet refs/heads/feature
  [ "$status" -ne 0 ]
  run git ls-remote --heads origin feature
  [ -z "$output" ]
}

@test "the branch it deleted is named with the sha that brings it back" {
  finished_branch feature
  local sha
  sha="$(git rev-parse --short refs/heads/feature)"
  pr_list '[ { "number": 7, "headRefName": "feature", "state": "MERGED" } ]'

  origin_cli prune --yes
  [[ "$stderr" == *"feature at ${sha}"* ]]
  [[ "$stderr" == *"git branch feature ${sha}"* ]]
}

@test "a branch no pull request holds is suggested, and stays where it is" {
  finished_branch orphan
  pr_list '[]'

  origin_cli prune --yes
  [ "$status" -eq 0 ]

  git show-ref --verify --quiet refs/heads/orphan
  [[ "$stderr" == *"git branch -D orphan"* ]]
  [[ "$stderr" == *"yours to delete"* ]]
}

@test "an open pull request keeps its branch" {
  finished_branch feature
  pr_list '[ { "number": 7, "headRefName": "feature", "state": "OPEN" } ]'

  origin_cli prune --yes
  git show-ref --verify --quiet refs/heads/feature
  [[ "$stderr" == *"pull request #7 is still open"* ]]
}

@test "a branch holding a commit no remote has is kept, whatever the forge says" {
  finished_branch feature
  git checkout -q feature
  git commit -q --allow-empty -m "Not pushed anywhere"
  git checkout -q main
  pr_list '[ { "number": 7, "headRefName": "feature", "state": "MERGED" } ]'

  origin_cli prune --yes
  git show-ref --verify --quiet refs/heads/feature
  [[ "$stderr" == *"1 commit no remote has"* ]]
}

@test "the branch you are standing on is kept" {
  finished_branch feature
  git checkout -q feature
  pr_list '[ { "number": 7, "headRefName": "feature", "state": "MERGED" } ]'

  origin_cli prune --yes
  git show-ref --verify --quiet refs/heads/feature
  [[ "$stderr" == *"the branch you are on"* ]]
}

@test "a branch checked out in another worktree is kept" {
  finished_branch feature
  git worktree add -q "${ROOT}/elsewhere" feature
  pr_list '[ { "number": 7, "headRefName": "feature", "state": "MERGED" } ]'

  origin_cli prune --yes
  git show-ref --verify --quiet refs/heads/feature
  [[ "$stderr" == *"checked out in another worktree"* ]]
}

@test "an unfinished branch is counted, never listed and never deleted" {
  git checkout -qb unfinished
  commit_file unfinished.txt yes "Work nobody merged"
  git checkout -q main
  pr_list '[]'

  origin_cli prune --yes
  git show-ref --verify --quiet refs/heads/unfinished
  [[ "$stderr" == *"1 branch holds work"* ]]
  [[ "$stderr" != *"git branch -D unfinished"* ]]
}

@test "--dry-run deletes nothing, here or on the remote" {
  finished_branch feature
  pr_list '[ { "number": 7, "headRefName": "feature", "state": "MERGED" } ]'

  origin_cli prune --dry-run
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"would run: git branch -D feature"* ]]

  git show-ref --verify --quiet refs/heads/feature
  run git ls-remote --heads origin feature
  [ -n "$output" ]
}

@test "commentary is on stderr, and stdout carries nothing" {
  finished_branch feature
  pr_list '[ { "number": 7, "headRefName": "feature", "state": "MERGED" } ]'

  origin_cli prune --yes
  [ -z "$output" ]
}
