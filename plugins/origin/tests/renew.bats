#!/usr/bin/env bats
#
# renew: rebasing a branch that can be rebased, and starting the next one
# when it cannot.

load helpers/repo

setup() {
  setup_repo
}

@test "a dirty tree is a refusal, and the way out is named" {
  git checkout -qb feature
  printf 'uncommitted\n' >>README.md

  origin_cli renew --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"working tree is dirty"* ]]
  [[ "$stderr" == *"--autostash"* ]]
}

@test "a branch is rebased onto a head branch that moved" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli renew --yes
  [ "$status" -eq 0 ]
  run git log --oneline -1 --format=%s "origin/main"
  [ "$output" = "A commit from somewhere else" ]
  run git merge-base --is-ancestor origin/main feature
  [ "$status" -eq 0 ]
}

@test "a rebase says what it rewrites, and the restore line is exactly runnable" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  local before
  before="$(git rev-parse --short feature)"
  upstream_moves

  origin_cli renew --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"This will rewrite:"* ]]
  [[ "$stderr" == *"feature at ${before}"* ]]
  [ "$(git rev-parse --short feature)" != "$before" ]

  local line
  line="$(printf '%s\n' "$stderr" | grep 'restore: git reset' | sed 's/.*restore: //')"
  [ -n "$line" ]
  eval "$line"
  [ "$(git rev-parse --short feature)" = "$before" ]
}

@test "a branch already on top is left alone" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"

  origin_cli renew --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"already on top of origin/main"* ]]
}

@test "the head branch fast-forwards" {
  upstream_moves
  origin_cli renew --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"main is at origin/main"* ]]
  run git log --oneline -1 --format=%s main
  [ "$output" = "A commit from somewhere else" ]
}

@test "local commits on the head branch are shown, not discarded" {
  commit_file accident.txt yes "A commit that should not be here"
  upstream_moves

  origin_cli renew --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"A commit that should not be here"* ]]
  [[ "$stderr" == *"would lose them"* ]]
  run git log --oneline -1 --format=%s main
  [ "$output" = "A commit that should not be here" ]
}

@test "a conflict stops, names the files, and leaves both ways out open" {
  git checkout -qb feature
  commit_file contested.txt mine "Mine"
  upstream_moves contested.txt theirs "Theirs"

  origin_cli renew --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stopped on a conflict"* ]]
  [[ "$stderr" == *"contested.txt"* ]]
  [[ "$stderr" == *"git rebase --continue"* ]]
  [[ "$stderr" == *"git rebase --abort"* ]]

  # Still mid-rebase: nothing was resolved, skipped or thrown away.
  run git rebase --abort
  [ "$status" -eq 0 ]
}

@test "a rebase already in progress is not started over" {
  git checkout -qb feature
  commit_file contested.txt mine "Mine"
  upstream_moves contested.txt theirs "Theirs"
  git fetch -q origin
  git rebase origin/main || true

  origin_cli renew --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already in progress"* ]]
  git rebase --abort
}

@test "--autostash carries uncommitted work across the rebase" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  printf 'work in progress\n' >>README.md
  upstream_moves

  origin_cli renew --yes --autostash
  [ "$status" -eq 0 ]
  run grep -c "work in progress" README.md
  [ "$output" = "1" ]
  run git merge-base --is-ancestor origin/main feature
  [ "$status" -eq 0 ]
}

@test "a detached HEAD is refused rather than guessed at" {
  git checkout -q --detach
  origin_cli renew --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"detached"* ]]
}

@test "the push is leased, never forced" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git push -q -u origin feature
  upstream_moves

  origin_cli renew --yes --push --dry-run --verbose
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"--force-with-lease --force-if-includes"* ]]
  [[ "$stderr" != *"push --force "* ]]
}

@test "a branch the remote has never seen is pushed plainly: no lease, no force" {
  # A lease is a claim about a ref this clone has seen, and there is none.
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli renew --yes --push --verbose
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"push --set-upstream origin feature"* ]]
  [[ "$stderr" != *"--force-with-lease"* ]]
  [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feature" ]
}

# A branch made by hand off the head branch and pushed without `-u`: the
# remote has it, and this clone has a remote-tracking ref for it, but no
# upstream is configured.
push_by_hand() {
  git checkout -q -b feature origin/main
  commit_file mine.txt yes "My work"
  git push -q origin feature
  git config --unset branch.feature.remote 2>/dev/null || true
  git config --unset branch.feature.merge 2>/dev/null || true
}

@test "a branch pushed by hand without an upstream still pushes on clean history" {
  push_by_hand
  commit_file more.txt yes "More work"

  origin_cli renew --yes --push
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"pushed feature"* ]]
  [[ "$stderr" != *"got to the name first"* ]]
  [ "$(git rev-parse feature)" = "$(git rev-parse origin/feature)" ]
  # And the upstream is recorded, so the next push does not work it out again.
  [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feature" ]
}

@test "a branch pushed by hand and then rebased is pushed, not renamed" {
  # The rebase makes the push a non-fast-forward. That is this branch being
  # brought up to date, not a name somebody else took, and the pair of lease
  # flags is what tells them apart: this clone had those commits.
  push_by_hand
  upstream_moves

  origin_cli renew --yes --push
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"pushed feature"* ]]
  [[ "$stderr" != *"git branch -m"* ]]
  [ "$(git rev-parse feature)" = "$(git rev-parse origin/feature)" ]
  run git merge-base --is-ancestor origin/main feature
  [ "$status" -eq 0 ]
}

@test "a first push onto a name somebody else took is refused, and the next number is named" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature
  origin_cli renew --yes --auto
  [ "$status" -eq 0 ]

  local name today
  today="$(date +%Y-%m-%d)"
  name="feature-${today}_001"
  [ "$(git rev-parse --abbrev-ref HEAD)" = "$name" ]
  commit_file later.txt yes "Later work"

  # Somebody else pushes a branch of that name, from a clone of their own.
  local other="${ROOT}/racer"
  git clone -q "$UPSTREAM" "$other"
  (
    cd "$other" || exit 1
    git checkout -q -b "$name" origin/main
    printf 'theirs\n' >theirs.txt
    git add theirs.txt
    git commit -qm "Theirs"
    git push -q origin "$name"
  )
  rm -rf "$other"

  origin_cli renew --yes --push
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"never had"* ]]
  [[ "$stderr" == *"git branch -m feature-${today}_002"* ]]

  # Their commit is still there. The lease refused precisely because this
  # clone never had it.
  git fetch -q origin
  run git log --oneline -1 "origin/${name}"
  [[ "$output" == *"Theirs"* ]]

  # And doing what it said works.
  git branch -m "feature-${today}_002"
  origin_cli renew --yes --push
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feature-${today}_002" ]
}

@test "a repository with no remote is not pushed" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git remote remove origin
  git config git-worktree-plugin.headBranch main

  origin_cli renew --yes --push
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no remote"* ]]
}

# --------------------------------------------------------------------------
# A branch whose change is already in the head branch
# --------------------------------------------------------------------------

@test "a finished branch is not rebased, and both ways to name the next one are given" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature

  origin_cli renew --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"squash-merged"* ]]
  [[ "$stderr" == *"--branch <name>"* ]]
  [[ "$stderr" == *"--auto"* ]]
  # Nothing moved.
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
}

@test "--auto starts the next branch from the head branch and leaves this one alone" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature
  local before
  before="$(git rev-parse feature)"

  origin_cli renew --yes --auto
  [ "$status" -eq 0 ]

  local expected
  expected="feature-$(date +%Y-%m-%d)_001"
  [ "$(git rev-parse --abbrev-ref HEAD)" = "$expected" ]
  [ "$(git rev-parse "$expected")" = "$(git rev-parse origin/main)" ]
  # The branch it came from is exactly where it was.
  [ "$(git rev-parse feature)" = "$before" ]
  [[ "$stderr" == *"feature is untouched"* ]]
}

@test "the next branch does not take the head branch as its upstream" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature

  origin_cli renew --yes --auto
  [ "$status" -eq 0 ]
  run git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
  [ "$status" -ne 0 ]
}

@test "a second renewal on the same day takes the next number" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature

  git checkout -q feature
  origin_cli renew --yes --auto
  [ "$status" -eq 0 ]
  git checkout -q feature
  origin_cli renew --yes --auto
  [ "$status" -eq 0 ]

  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-$(date +%Y-%m-%d)_002" ]
}

@test "renewing a renewed branch does not stack suffixes" {
  local today
  today="$(date +%Y-%m-%d)"
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature
  origin_cli renew --yes --auto
  [ "$status" -eq 0 ]

  # Work on the new branch, and get that merged too.
  commit_file second.txt yes "Second round"
  squash_merge_branch "feature-${today}_001"
  git checkout -q "feature-${today}_001"

  origin_cli renew --yes --auto
  [ "$status" -eq 0 ]
  # A sibling, not a name with two dates in it.
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-${today}_002" ]
}

@test "a branch carrying nothing is empty rather than finished" {
  # It points at the head branch, so every merge test says it is merged. That
  # is not a reason to start another branch off it, nor to refuse to push it.
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature
  origin_cli renew --yes --auto
  [ "$status" -eq 0 ]

  origin_cli renew --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"already on top of origin/main"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-$(date +%Y-%m-%d)_001" ]
}

@test "--branch takes the name given, and refuses one already in use" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature

  git checkout -q feature
  origin_cli renew --yes --branch next-thing
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "next-thing" ]

  git checkout -q feature
  origin_cli renew --yes --branch next-thing
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already a branch called next-thing"* ]]
}

@test "--branch and --auto together are refused rather than one being picked" {
  origin_cli renew --yes --branch a --auto
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"pass one"* ]]
}

@test "naming a branch for a rebase in place is refused, and --squash is named" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli renew --yes --branch elsewhere
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unfinished"* ]]
  [[ "$stderr" == *"--squash"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
}

# --------------------------------------------------------------------------
# --squash: the whole change, onto a new branch off the head branch
# --------------------------------------------------------------------------

@test "--squash carries the branch onto a new one in a single commit" {
  git checkout -qb feature
  commit_file one.txt one "One"
  commit_file two.txt two "Two"
  upstream_moves
  local before
  before="$(git rev-parse feature)"

  origin_cli renew --yes --squash --branch carried
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "carried" ]
  # One commit, holding both files, on top of the head branch.
  [ "$(git rev-list --count origin/main..carried)" = "1" ]
  [ -f one.txt ]
  [ -f two.txt ]
  [ -f elsewhere.txt ]
  run git merge-base --is-ancestor origin/main carried
  [ "$status" -eq 0 ]
  # The branch it came from never moved.
  [ "$(git rev-parse feature)" = "$before" ]
}

@test "the carried commit says where it came from" {
  git checkout -qb feature
  commit_file one.txt one "One"
  commit_file two.txt two "Two"
  upstream_moves

  origin_cli renew --yes --squash --branch carried
  [ "$status" -eq 0 ]
  run git log -1 --format=%B carried
  [[ "$output" == *"feature, carried onto main"* ]]
  [[ "$output" == *"2 commit(s) on feature"* ]]
}

@test "a rebase that replays merged commits conflicts where the carry does not" {
  # The branch was squash-merged, then grew another commit. Its old commits
  # are content the head branch already has, so a rebase replays them into
  # themselves; the carry compares trees and never mentions them.
  git checkout -qb feature
  commit_file shared.txt one "One"
  commit_file shared.txt two "Two"
  squash_merge_branch feature
  git checkout -q feature
  commit_file other.txt three "Three"

  origin_cli renew --yes --squash --branch carried
  [ "$status" -eq 0 ]
  [ "$(git rev-list --count origin/main..carried)" = "1" ]
  [ -f other.txt ]
  run git log --oneline origin/main..carried
  [ "$(printf '%s\n' "$output" | grep -c .)" = "1" ]
}

@test "a carry that conflicts stops once, names the way back, and moves nothing" {
  git checkout -qb feature
  commit_file contested.txt mine "Mine"
  upstream_moves contested.txt theirs "Theirs"
  local before
  before="$(git rev-parse feature)"

  origin_cli renew --yes --squash --branch carried
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stopped on a conflict"* ]]
  [[ "$stderr" == *"contested.txt"* ]]
  # `git merge --abort` cannot back out a --squash merge; this is what does.
  [[ "$stderr" == *"git reset --merge"* ]]
  [[ "$stderr" != *"git merge --abort"* ]]
  [ "$(git rev-parse feature)" = "$before" ]

  # And the way back works.
  git reset -q --merge
  git checkout -q feature
  git branch -D carried
  [ "$(git rev-parse feature)" = "$before" ]
}

# A branch squash-merged upstream that then grew a commit: the rebase replays
# commits the head branch already has and stops on them, while the carry
# compares trees and never mentions them.
setup_replay_conflict() {
  git checkout -qb feature
  commit_file shared.txt one "One"
  commit_file shared.txt two "Two"
  squash_merge_branch feature
  git checkout -q feature
  commit_file other.txt three "Three"
  upstream_moves
}

@test "a rebase conflict offers the carry when the carry would work" {
  setup_replay_conflict

  origin_cli renew --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stopped on a conflict"* ]]
  [[ "$stderr" == *"origin renew --squash --auto"* ]]
  # And it says what the offer costs.
  [[ "$stderr" == *"becoming one"* ]]
  git rebase --abort
}

@test "a rebase conflict does not offer a carry that would conflict too" {
  # Both sides changed the same file. No route avoids that, and sending
  # somebody down a second one costs them the resolutions they already made.
  git checkout -qb feature
  commit_file contested.txt mine "Mine"
  upstream_moves contested.txt theirs "Theirs"

  origin_cli renew --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stopped on a conflict"* ]]
  [[ "$stderr" != *"origin renew --squash --auto"* ]]
  [[ "$stderr" == *"would conflict here too"* ]]
  git rebase --abort
}

@test "--probe says whether the carry would apply, and changes nothing" {
  setup_replay_conflict
  local before
  before="$(git rev-parse feature)"

  origin_cli renew --yes --squash --probe
  [ "$status" -eq 0 ]
  [ "$output" = "clean" ]
  [ "$(git rev-parse feature)" = "$before" ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
  run git status --porcelain
  [ -z "$output" ]
}

@test "--probe says conflicts when the two sides genuinely disagree" {
  git checkout -qb feature
  commit_file contested.txt mine "Mine"
  upstream_moves contested.txt theirs "Theirs"

  origin_cli renew --yes --squash --probe
  [ "$status" -eq 0 ]
  [ "$output" = "conflicts" ]
}

@test "--probe answers on stdout, so it survives --quiet" {
  setup_replay_conflict

  origin_cli renew --yes --squash --probe --quiet
  [ "$status" -eq 0 ]
  [ "$output" = "clean" ]
}

@test "--probe without --squash says which flag it belongs to" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"

  origin_cli renew --yes --probe
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--probe answers for --squash"* ]]
}

@test "--squash on a branch with nothing left says so instead of committing nothing" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature

  origin_cli renew --yes --squash --branch carried
  [ "$status" -eq 0 ]
  [ "$(git rev-parse carried)" = "$(git rev-parse origin/main)" ]
}

@test "--dry-run on a finished branch creates nothing" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature

  origin_cli renew --yes --auto --dry-run
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"would run: git switch --create"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
  run git show-ref --verify --quiet "refs/heads/feature-$(date +%Y-%m-%d)_001"
  [ "$status" -ne 0 ]
}

@test "--autostash carries uncommitted work onto the next branch" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature
  printf 'work in progress\n' >>README.md

  origin_cli renew --yes --auto --autostash
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-$(date +%Y-%m-%d)_001" ]
  run grep -c "work in progress" README.md
  [ "$output" = "1" ]
}

@test "a new branch and the head branch are not the same request" {
  origin_cli renew --yes --auto
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"head branch"* ]]
}
