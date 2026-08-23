#!/usr/bin/env bats
#
# Telling a finished branch from an unfinished one, which is the one judgement
# `wt clean` cannot get wrong.

load helpers/repo

setup() {
  setup_repo
  # shellcheck source=../lib/common.sh
  . "${BATS_TEST_DIRNAME}/../lib/common.sh"
  # shellcheck source=../lib/repo.sh
  . "${BATS_TEST_DIRNAME}/../lib/repo.sh"
  # shellcheck source=../lib/merged.sh
  . "${BATS_TEST_DIRNAME}/../lib/merged.sh"
}

@test "a squash-merged branch is recognised" {
  git checkout -qb squashed
  commit_file feature.txt one "First half"
  commit_file feature.txt two "Second half"
  squash_merge_branch squashed
  git fetch -q origin

  run merged_reason squashed origin/main
  [ "$status" -eq 0 ]
  [ "$output" = "squash-merged" ]
}

@test "an unmerged branch is not mistaken for a squash-merged one" {
  git checkout -qb unmerged
  commit_file unmerged.txt yes "Work nobody merged"
  git checkout -q main

  run merged_reason unmerged origin/main
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "a branch merged the ordinary way is recognised, and says so" {
  git checkout -qb ordinary
  commit_file ordinary.txt yes "Ordinary work"
  git checkout -q main
  git merge -q --no-ff ordinary -m "Merge ordinary"
  git push -q origin main
  git fetch -q origin

  run merged_reason ordinary origin/main
  [ "$status" -eq 0 ]
  [ "$output" = "merged" ]
}

@test "a branch that changes nothing is not work to protect" {
  git checkout -qb empty
  git commit -q --allow-empty -m "Nothing at all"
  git checkout -q main

  run merged_reason empty origin/main
  [ "$status" -eq 0 ]
  [ "$output" = "squash-merged" ]
}

@test "a branch squash-merged and then added to is unmerged again" {
  git checkout -qb more
  commit_file more.txt one "First"
  squash_merge_branch more
  git fetch -q origin
  git checkout -q more
  commit_file more.txt two "And more, after the squash"
  git checkout -q main

  run merged_reason more origin/main
  [ "$status" -ne 0 ]
}

@test "content decides, not reachability: a squash-merged branch has unpushed commits" {
  git checkout -qb never-pushed
  commit_file local.txt yes "Never pushed anywhere"
  squash_merge_branch never-pushed
  git fetch -q origin

  run merged_reason never-pushed origin/main
  [ "$status" -eq 0 ]
  [ "$output" = "squash-merged" ]

  # The branch's own commit is on no remote — the squash made a different one.
  # Counting commits would call this unfinished; comparing content does not.
  run merged_unpushed_count never-pushed
  [ "$output" = "1" ]
}

@test "a branch never pushed anywhere is entirely unpushed" {
  git checkout -qb never-pushed
  commit_file local.txt one "One"
  commit_file local.txt two "Two"
  run merged_unpushed_count never-pushed
  [ "$output" = "2" ]
}

@test "a branch level with its upstream has nothing unpushed" {
  git checkout -qb pushed
  commit_file p.txt yes "Pushed"
  git push -q -u origin pushed
  run merged_unpushed_count pushed
  [ "$output" = "0" ]
}
