#!/usr/bin/env bats
#
# sync: rebasing a branch that can be rebased, and starting the next one
# when it cannot.

load helpers/repo

setup() {
  setup_repo
}

@test "a dirty tree is a refusal, and the way out is named" {
  git checkout -qb feature
  printf 'uncommitted\n' >>README.md

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"working tree is dirty"* ]]
  [[ "$stderr" == *"--autostash"* ]]
}

@test "a branch is rebased onto a head branch that moved" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli sync --yes
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

  origin_cli sync --yes
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

@test "a tag sharing the branch's name does not decide what the branch is" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  local before
  before="$(git rev-parse --short refs/heads/feature)"
  # On the commit the branch left main at. Read for the branch it names the
  # wrong commit to go back to, and it turns the branch's own name into
  # `heads/feature`, which is the shortest spelling git can still resolve.
  git tag feature main
  upstream_moves

  origin_cli sync --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"commit(s) on feature,"* ]]
  [[ "$stderr" == *"feature at ${before}"* ]]
  # `run` overwrites $stderr, so the line comes out of it first.
  local line
  line="$(printf '%s\n' "$stderr" | grep 'restore: git reset' | sed 's/.*restore: //')"
  [ -n "$line" ]

  run git merge-base --is-ancestor refs/remotes/origin/main refs/heads/feature
  [ "$status" -eq 0 ]

  eval "$line"
  [ "$(git rev-parse --short refs/heads/feature)" = "$before" ]
}

@test "a branch already on top is left alone" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"

  origin_cli sync --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"already on top of origin/main"* ]]
}

@test "the head branch fast-forwards" {
  upstream_moves
  origin_cli sync --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"main is at origin/main"* ]]
  run git log --oneline -1 --format=%s main
  [ "$output" = "A commit from somewhere else" ]
}

@test "local commits on the head branch are shown, not discarded" {
  commit_file accident.txt yes "A commit that should not be here"
  upstream_moves

  origin_cli sync --yes
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

  origin_cli sync --yes
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

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already in progress"* ]]
  git rebase --abort
}

@test "--autostash carries uncommitted work across the rebase" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  printf 'work in progress\n' >>README.md
  upstream_moves

  origin_cli sync --yes --autostash
  [ "$status" -eq 0 ]
  run grep -c "work in progress" README.md
  [ "$output" = "1" ]
  run git merge-base --is-ancestor origin/main feature
  [ "$status" -eq 0 ]
}

@test "a detached HEAD is refused rather than guessed at" {
  git checkout -q --detach
  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"detached"* ]]
}

@test "the push is leased, never forced" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git push -q -u origin feature
  upstream_moves

  origin_cli sync --yes --push --dry-run --verbose
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"--force-with-lease --force-if-includes"* ]]
  [[ "$stderr" != *"push --force "* ]]
}

@test "a branch the remote has never seen is pushed plainly: no lease, no force" {
  # A lease is a claim about a ref this clone has seen, and there is none.
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli sync --yes --push --verbose
  [ "$status" -eq 0 ]
  # The refspec is spelled in full: a bare name matches a tag as well as a
  # branch, and git refuses a push whose source matches both.
  [[ "$stderr" == *"push --set-upstream origin refs/heads/feature"* ]]
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

  origin_cli sync --yes --push
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

  origin_cli sync --yes --push
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"pushed feature"* ]]
  [[ "$stderr" != *"git branch -m"* ]]
  [ "$(git rev-parse feature)" = "$(git rev-parse origin/feature)" ]
  run git merge-base --is-ancestor origin/main feature
  [ "$status" -eq 0 ]
}

@test "a first push onto a name somebody else took is refused, and renaming is named" {
  origin_cli new next-thing --yes
  [ "$status" -eq 0 ]
  commit_file later.txt yes "Later work"

  # Somebody else pushes a branch of that name, from a clone of their own.
  local other="${ROOT}/racer"
  git clone -q "$UPSTREAM" "$other"
  (
    cd "$other" || exit 1
    git checkout -q -b next-thing origin/main
    printf 'theirs\n' >theirs.txt
    git add theirs.txt
    git commit -qm "Theirs"
    git push -q origin next-thing
  )
  rm -rf "$other"

  origin_cli sync --yes --push
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"never had"* ]]
  # The branch to look at is named in full: this is the moment somebody decides
  # whether the work on the remote is theirs to overwrite, and a tag of that
  # name would answer instead.
  [[ "$stderr" == *"git log refs/remotes/origin/next-thing"* ]]
  [[ "$stderr" == *"git branch -m"* ]]

  # Their commit is still there. The lease refused precisely because this
  # clone never had it.
  git fetch -q origin
  run git log --oneline -1 origin/next-thing
  [[ "$output" == *"Theirs"* ]]

  # And doing what it said works.
  git branch -m another-thing
  origin_cli sync --yes --push
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/another-thing" ]
}

@test "a repository with no remote is not pushed" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  git remote remove origin

  origin_cli sync --yes --push
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no remote"* ]]
}

# --------------------------------------------------------------------------
# A branch whose change is already in the head branch
# --------------------------------------------------------------------------

@test "a finished branch is not rebased, and the way on is named" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"squash-merged"* ]]
  [[ "$stderr" == *"origin new <name>"* ]]
  # Nothing moved.
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
}

@test "a carried branch does not take the head branch as its upstream" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli sync --yes --squash --branch carried
  [ "$status" -eq 0 ]
  run git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
  [ "$status" -ne 0 ]
}

@test "a branch carrying nothing is empty rather than finished" {
  # It points at the head branch, so every merge test says it is merged. That
  # is not a reason to refuse to push it.
  origin_cli new next-thing --yes
  [ "$status" -eq 0 ]

  origin_cli sync --yes
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"already on top of origin/main"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "next-thing" ]
}

@test "--branch takes the name given, and refuses one already in use" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli sync --yes --squash --branch next-thing
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "next-thing" ]

  git checkout -q feature
  origin_cli sync --yes --squash --branch next-thing
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already a branch called next-thing"* ]]
}

@test "a carry with no name is refused rather than given a generated one" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli sync --yes --squash
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--branch <name>"* ]]
}

@test "naming a branch for a rebase in place is refused, and --squash is named" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli sync --yes --branch elsewhere
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

  origin_cli sync --yes --squash --branch carried
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

  origin_cli sync --yes --squash --branch carried
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

  origin_cli sync --yes --squash --branch carried
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

  origin_cli sync --yes --squash --branch carried
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

@test "the replay conflict is caught before the rebase, not during it" {
  # Two commits squash-merged and one added after: the shape the boundary scan
  # exists for. The rebase that would stop on the first two never starts.
  setup_replay_conflict

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"squashed into one"* ]]
  [[ "$stderr" == *"origin sync --branch <name>"* ]]
  run git rev-parse --absolute-git-dir
  [ ! -d "${output}/rebase-merge" ]
  [ ! -d "${output}/rebase-apply" ]
}

@test "the rest of a replay-conflicting branch keeps its own commits" {
  setup_replay_conflict

  origin_cli sync --yes --branch the-rest
  [ "$status" -eq 0 ]
  [ "$(git rev-list --count refs/remotes/origin/main..HEAD)" = "1" ]
  run git log --format=%s -1
  [ "$output" = "Three" ]
}

@test "a branch too long to scan falls back to the rebase and its offer" {
  setup_replay_conflict

  MERGED_BOUNDARY_LIMIT=0 origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stopped on a conflict"* ]]
  [[ "$stderr" == *"origin sync --squash --branch <name>"* ]]
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

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stopped on a conflict"* ]]
  [[ "$stderr" != *"origin sync --squash --auto"* ]]
  [[ "$stderr" == *"would conflict here too"* ]]
  git rebase --abort
}

@test "--probe says whether the carry would apply, and changes nothing" {
  setup_replay_conflict
  local before
  before="$(git rev-parse feature)"

  origin_cli sync --yes --squash --probe
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

  origin_cli sync --yes --squash --probe
  [ "$status" -eq 0 ]
  [ "$output" = "conflicts" ]
}

@test "--probe answers on stdout, so it survives --quiet" {
  setup_replay_conflict

  origin_cli sync --yes --squash --probe --quiet
  [ "$status" -eq 0 ]
  [ "$output" = "clean" ]
}

@test "--probe without --squash says which flag it belongs to" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"

  origin_cli sync --yes --probe
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--probe answers for --squash"* ]]
}

@test "--squash on a branch with nothing left says so instead of committing nothing" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature

  # Finished is finished, whichever route was asked for: a carry here would
  # commit nothing, so the answer is the same one a plain sync gives.
  origin_cli sync --yes --squash --branch carried
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"origin new <name>"* ]]
  run git show-ref --verify --quiet refs/heads/carried
  [ "$status" -ne 0 ]
}

@test "--dry-run on a carry creates nothing" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli sync --yes --squash --branch carried --dry-run
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"would run: git switch --create"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
  run git show-ref --verify --quiet refs/heads/carried
  [ "$status" -ne 0 ]
}

@test "--autostash carries uncommitted work onto the carried branch" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves
  printf 'work in progress\n' >>README.md

  origin_cli sync --yes --squash --branch carried --autostash
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "carried" ]
  run grep -c "work in progress" README.md
  [ "$output" = "1" ]
}

@test "--branch on the head branch is refused rather than acted on" {
  origin_cli sync --yes --branch somewhere
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"head branch"* ]]
}


# --------------------------------------------------------------------------
# A branch the head branch has only part of
# --------------------------------------------------------------------------

# Two commits squash-merged, two added afterwards. `git cherry` marks all four
# as new, because a squash rewrites them into one patch nothing matches.
partly_absorbed() {
  git checkout -qb feature
  commit_file a.txt yes "A"
  commit_file b.txt yes "B"
  git checkout -q main
  git merge -q --squash feature
  git commit -qm "A and B, squashed (#1)"
  git push -q origin main
  git checkout -q feature
  commit_file c.txt yes "C"
  commit_file d.txt yes "D"
  git fetch -q origin
}

@test "a partly absorbed branch is named rather than rebased" {
  partly_absorbed

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"2 commit(s) of feature"* ]]
  [[ "$stderr" == *"origin sync --branch <name>"* ]]
  [[ "$stderr" == *"--squash --branch <name>"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
}

@test "the rest goes onto a new branch as its own commits" {
  partly_absorbed
  local before
  before="$(git rev-parse feature)"

  origin_cli sync --yes --branch the-rest
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "the-rest" ]

  # C and D, still two commits, on top of the squashed one.
  [ "$(git rev-list --count refs/remotes/origin/main..HEAD)" = "2" ]
  run git log --format=%s refs/remotes/origin/main..HEAD
  [[ "$output" == *"D"* ]]
  [[ "$output" == *"C"* ]]
  # Everything is there: a.txt and b.txt from the squash, c.txt and d.txt from
  # the pick.
  [ -f a.txt ] && [ -f b.txt ] && [ -f c.txt ] && [ -f d.txt ]
  # And the branch it came from has not moved.
  [ "$(git rev-parse feature)" = "$before" ]
}

@test "the new branch does not take the head branch as its upstream" {
  partly_absorbed

  origin_cli sync --yes --branch the-rest
  [ "$status" -eq 0 ]
  run git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
  [ "$status" -ne 0 ]
}

@test "a name already in use is refused before anything is created" {
  partly_absorbed
  git branch the-rest

  origin_cli sync --yes --branch the-rest
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already a branch called the-rest"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
}

@test "a dirty tree is refused rather than carried into the pick" {
  partly_absorbed
  printf 'work in progress\n' >>README.md

  origin_cli sync --yes --branch the-rest
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--commit"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature" ]
}

@test "a fully absorbed branch is still finished, not partly absorbed" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  squash_merge_branch feature
  git checkout -q feature

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"squash-merged"* ]]
  [[ "$stderr" == *"origin new <name>"* ]]
}

@test "a branch with nothing of it upstream is rebased as before" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves

  origin_cli sync --yes
  [ "$status" -eq 0 ]
  run git merge-base --is-ancestor refs/remotes/origin/main refs/heads/feature
  [ "$status" -eq 0 ]
}

# --------------------------------------------------------------------------
# Committing what is in the tree
# --------------------------------------------------------------------------

@test "--message commits the tracked changes and then syncs" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  upstream_moves
  printf 'more\n' >>mine.txt

  origin_cli sync --yes --message "Say more"
  [ "$status" -eq 0 ]
  run git log --format=%s -1 feature
  [ "$output" = "Say more" ]
  run git status --porcelain
  [ -z "$output" ]
  run git merge-base --is-ancestor refs/remotes/origin/main refs/heads/feature
  [ "$status" -eq 0 ]
}

@test "untracked files are listed and left where they are" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  printf 'more\n' >>mine.txt
  printf 'secret\n' >.env

  origin_cli sync --yes --message "Say more"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Untracked, and left alone"* ]]
  [[ "$stderr" == *".env"* ]]
  run git ls-files --error-unmatch .env
  [ "$status" -ne 0 ]
}

@test "--commit with no terminal says which flag carries the message" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  printf 'more\n' >>mine.txt

  origin_cli sync --yes --commit
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--message <text>"* ]]
  run git status --porcelain
  [ -n "$output" ]
}

@test "a dirty tree with neither flag names both of them" {
  git checkout -qb feature
  commit_file mine.txt yes "My work"
  printf 'more\n' >>mine.txt

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--commit"* ]]
  [[ "$stderr" == *"--autostash"* ]]
}

# --------------------------------------------------------------------------
# Half-finished operations
# --------------------------------------------------------------------------

@test "a cherry-pick in progress is refused by name" {
  git checkout -qb feature
  commit_file shared.txt theirs "Theirs"
  git checkout -q main
  commit_file shared.txt ours "Ours"
  run git cherry-pick feature
  [ -f "$(git rev-parse --absolute-git-dir)/CHERRY_PICK_HEAD" ]

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cherry-pick is already in progress"* ]]
  [[ "$stderr" == *"git cherry-pick --abort"* ]]
}

@test "a merge in progress is refused by name" {
  git checkout -qb feature
  commit_file shared.txt theirs "Theirs"
  git checkout -q main
  commit_file shared.txt ours "Ours"
  run git merge feature
  [ -f "$(git rev-parse --absolute-git-dir)/MERGE_HEAD" ]

  origin_cli sync --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"merge is already in progress"* ]]
  [[ "$stderr" == *"git merge --abort"* ]]
}
