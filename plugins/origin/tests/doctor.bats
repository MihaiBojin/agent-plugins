#!/usr/bin/env bats
#
# Preflight: every row carries the command that fixes it.

load helpers/repo

setup() {
  setup_repo
}

@test "a healthy repository with no forge passes, warning about the forge" {
  origin_cli doctor
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"git"* ]]
  [[ "$stderr" == *"head branch"* ]]
  [[ "$stderr" == *"main"* ]]
}

@test "an unresolvable head branch names the config key that fixes it" {
  git remote remove origin
  git branch -m main trunk-a
  git branch trunk-b
  git checkout -q --detach

  origin_cli doctor
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"git-worktree-plugin.headBranch"* ]]
}

@test "an unauthenticated forge CLI names the login command" {
  stub_forge https://github.com/owner/repo.git
  export ORIGIN_STUB_GH_UNAUTHENTICATED=1

  origin_cli doctor
  [[ "$stderr" == *"gh auth login --hostname github.com"* ]]
}

@test "read-only permission is a failure, and says so" {
  stub_forge https://github.com/owner/repo.git
  stub_json repo.json <<'JSON'
{ "viewerPermission": "READ", "viewerDefaultMergeMethod": "SQUASH",
  "squashMergeAllowed": true, "mergeCommitAllowed": true, "rebaseMergeAllowed": true }
JSON

  origin_cli doctor
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"merging needs write"* ]]
}

@test "the repository's merge methods are reported" {
  stub_forge https://github.com/owner/repo.git
  stub_json repo.json <<'JSON'
{ "viewerPermission": "WRITE", "viewerDefaultMergeMethod": "REBASE",
  "squashMergeAllowed": false, "mergeCommitAllowed": true, "rebaseMergeAllowed": true }
JSON

  origin_cli doctor
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"default rebase"* ]]
  [[ "$stderr" == *"merge,rebase"* ]]
}

@test "doctor reports on the repository without changing it" {
  git symbolic-ref --delete "refs/remotes/origin/HEAD"

  origin_cli doctor
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"main"* ]]
  # It read the answer off the remote; it did not record it here.
  run git symbolic-ref --quiet "refs/remotes/origin/HEAD"
  [ "$status" -ne 0 ]
}

@test "outside a repository it says so instead of guessing" {
  cd "$ROOT"
  origin_cli doctor
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not inside a git repository"* ]]
}
