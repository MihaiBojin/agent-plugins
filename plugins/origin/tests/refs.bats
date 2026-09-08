#!/usr/bin/env bats
#
# A tag and a branch of the same name.
#
# `git rev-parse feature` prefers `refs/tags/feature` over `refs/heads/feature`,
# so a repository holding both answers every question about the branch with the
# tag instead. What this plugin reads that way is whether a branch is finished
# and which commit its restore line names, so a bare name is never what it asks
# with.

load helpers/repo

setup() {
  setup_repo
  # shellcheck source=../lib/common.sh
  . "${BATS_TEST_DIRNAME}/../lib/common.sh"
  # shellcheck source=../lib/repo.sh
  . "${BATS_TEST_DIRNAME}/../lib/repo.sh"
  # shellcheck source=../lib/merged.sh
  . "${BATS_TEST_DIRNAME}/../lib/merged.sh"
  # shellcheck source=../lib/worktree.sh
  . "${BATS_TEST_DIRNAME}/../lib/worktree.sh"
}

# A branch carrying a commit nobody merged, with a tag of the same name left on
# the head branch.
shadowed_branch() {
  git checkout -qb "$1"
  commit_file "${1}.txt" yes "Work nobody merged"
  git checkout -q main
  git tag "$1" main
}

@test "the head branch is a full ref, and reads back as a person writes it" {
  run repo_head_ref
  [ "$output" = "refs/remotes/origin/main" ]

  run ref_name refs/remotes/origin/main
  [ "$output" = "origin/main" ]
  run ref_name refs/heads/feature
  [ "$output" = "feature" ]
  run ref_name v1.2.3
  [ "$output" = "v1.2.3" ]
}

@test "a repository with no remote names its head branch in full too" {
  git remote remove origin
  run repo_head_ref
  [ "$output" = "refs/heads/main" ]
}

@test "a head branch that is neither local nor remote-tracking is left as it is" {
  # A name nothing here recognises. Prefixing it would make
  # `refs/heads/nowhere`, which resolves to nothing at all; passed through, git
  # resolves it as it always did.
  run repo_head_ref_for nowhere
  [ "$output" = "nowhere" ]

  # And <remote>/HEAD still arrives as a full ref.
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  run repo_head_ref
  [ "$output" = "refs/remotes/origin/main" ]
}

@test "an origin/HEAD written by hand still names the branch" {
  # Pointed at the local branch rather than at this remote's copy of it, which
  # is what somebody replacing a missing origin/HEAD tends to write.
  git symbolic-ref refs/remotes/origin/HEAD refs/heads/main

  run repo_head_branch
  [ "$output" = "main" ]
  run repo_head_ref
  [ "$output" = "refs/remotes/origin/main" ]
}

@test "an unmerged branch shadowed by a tag is not finished" {
  shadowed_branch feature

  run merged_reason feature "$(repo_head_ref)"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "a tag called origin/main does not answer for the head branch" {
  git checkout -qb feature
  commit_file mine.txt yes "Work nobody merged"
  git checkout -q main
  # On the branch's own commit: read as the head branch, it would make every
  # branch look merged into it.
  git tag origin/main feature

  run repo_head_ref
  [ "$output" = "refs/remotes/origin/main" ]

  run merged_reason feature refs/remotes/origin/main
  [ "$status" -ne 0 ]
}

@test "a tag of the same name does not creep into a branch's own name" {
  # `git symbolic-ref --short HEAD` answers `heads/feature` here, because
  # `feature` alone no longer resolves to the branch.
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git tag feature main

  run repo_current_branch
  [ "$output" = "feature" ]
}

@test "a tag called origin/main does not creep into the head branch's name" {
  git tag origin/main main

  run repo_head_branch
  [ "$output" = "main" ]
}

@test "a shadowed branch's unpushed commits are still counted" {
  shadowed_branch feature

  run merged_unpushed_count feature
  [ "$output" = "1" ]
}

@test "a branch no longer at the recorded sha is not deleted" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git checkout -q main

  run worktree_delete_branch feature deadbee merged "$(git rev-parse main)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not deleting feature"* ]]
  git show-ref --verify --quiet refs/heads/feature
}

@test "a branch whose short sha is also a ref name is still deleted" {
  # `git rev-parse a1b2c3d` reads a branch or tag called `a1b2c3d` before it
  # reads the object, so the guard is given the whole sha rather than the
  # spelling the restore line carries.
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git checkout -q main
  git merge -q --no-ff feature -m "Merge feature"
  local sha
  sha="$(git rev-parse --short refs/heads/feature)"
  git tag "$sha" main

  run worktree_delete_branch feature "$sha" merged "$(git rev-parse refs/heads/feature)"
  [ "$status" -eq 0 ]
  [[ "$output" != *"not deleting"* ]]
  run git show-ref --verify --quiet refs/heads/feature
  [ "$status" -ne 0 ]
}

@test "a branch at the recorded sha is deleted, so the guard is not a refusal" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git checkout -q main
  git merge -q --no-ff feature -m "Merge feature"
  local sha
  sha="$(git rev-parse --short refs/heads/feature)"

  run worktree_delete_branch feature "$sha" merged "$(git rev-parse refs/heads/feature)"
  [ "$status" -eq 0 ]
  run git show-ref --verify --quiet refs/heads/feature
  [ "$status" -ne 0 ]
}
