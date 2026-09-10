#!/usr/bin/env bats
#
# new: a branch off the head branch as the remote has it.

load helpers/repo

setup() {
  setup_repo
}

@test "the branch starts from what the remote has, not from the local copy" {
  upstream_moves

  origin_cli new-branch next-thing --yes
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "next-thing" ]
  # The fetch happened first, so this is the commit the server had a moment
  # ago and not the one the local main is still sitting on.
  [ "$(git rev-parse next-thing)" = "$(git rev-parse refs/remotes/origin/main)" ]
  run git merge-base --is-ancestor refs/heads/main refs/heads/next-thing
  [ "$status" -eq 0 ]
}

@test "the new branch has no upstream, so a push cannot land on the head branch" {
  origin_cli new-branch next-thing --yes
  [ "$status" -eq 0 ]
  run git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
  [ "$status" -ne 0 ]
}

@test "a name that is already a branch is refused, and checking it out is named" {
  git branch taken

  origin_cli new-branch taken --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already a branch"* ]]
  [[ "$stderr" == *"git switch taken"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
}

@test "a name git will not take is refused before anything is fetched" {
  origin_cli new-branch "not a branch" --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not a valid branch name"* ]]
}

@test "with no name this branch names the next one" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"

  origin_cli new-branch --yes
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-$(date +%Y-%m-%d)_001" ]
  [ "$(git rev-parse HEAD)" = "$(git rev-parse refs/remotes/origin/main)" ]
}

@test "a second nameless run the same day takes the next number" {
  local today
  today="$(date +%Y-%m-%d)"
  git checkout -qb feature
  commit_file mine.txt yes "My work"

  origin_cli new-branch --yes
  [ "$status" -eq 0 ]
  git checkout -q feature
  origin_cli new-branch --yes
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-${today}_002" ]
}

@test "a generated name does not gain a second suffix" {
  local today
  today="$(date +%Y-%m-%d)"
  git checkout -qb feature
  commit_file mine.txt yes "My work"

  origin_cli new-branch --yes
  [ "$status" -eq 0 ]
  # Standing on feature-<today>_001, the next one is its sibling rather than a
  # name with two dates in it.
  origin_cli new-branch --yes
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-${today}_002" ]
}

@test "a name the remote holds is not generated, even with nothing local" {
  local today name
  today="$(date +%Y-%m-%d)"
  name="feature-${today}_001"
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git push -q origin "refs/heads/feature:refs/heads/${name}"
  git fetch -q origin

  origin_cli new-branch --yes
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-${today}_002" ]
}

@test "the head branch does not name the next one" {
  origin_cli new-branch --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"head branch"* ]]
  [[ "$stderr" == *"pass a name"* ]]
}

@test "a detached HEAD has no branch to name the next one after" {
  git checkout -q --detach HEAD

  origin_cli new-branch --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"detached"* ]]
}

@test "two names is an error, not a guess" {
  origin_cli new-branch one two --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"two"* ]]
  run git show-ref --verify --quiet refs/heads/one
  [ "$status" -ne 0 ]
}

@test "a tag called origin/main does not decide where the branch starts" {
  # `git rev-parse origin/main` reads refs/tags/origin/main before the
  # remote-tracking branch, so the base is named in full or it is the tag.
  commit_file stray.txt yes "A commit only this tag points at"
  git tag origin/main HEAD
  git checkout -q main
  git reset -q --keep HEAD~1

  origin_cli new-branch next-thing --yes
  [ "$status" -eq 0 ]
  [ "$(git rev-parse next-thing)" = "$(git rev-parse refs/remotes/origin/main)" ]
  [ "$(git rev-parse next-thing)" != "$(git rev-parse refs/tags/origin/main)" ]
}

@test "a dry run creates nothing and says what it would run" {
  origin_cli new-branch next-thing --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"would run: git switch --create next-thing --no-track"* ]]
  run git show-ref --verify --quiet refs/heads/next-thing
  [ "$status" -ne 0 ]
}

@test "nb is the same command" {
  origin_cli nb next-thing --yes
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "next-thing" ]
}
