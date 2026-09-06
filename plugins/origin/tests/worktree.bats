#!/usr/bin/env bats
#
# Worktrees, through the command line, which is the contract.

load helpers/repo

setup() {
  setup_repo
}

@test "add: branches from the head branch and lands at root/branch/repo" {
  origin_cli gwa feature
  [ "$status" -eq 0 ]
  [ "$output" = "${WORKTREES}/feature/proj" ]
  [ "$(git -C "$output" rev-parse --abbrev-ref HEAD)" = "feature" ]
}

@test "add: a new branch does not track the head branch" {
  origin_cli gwa feature
  run git rev-parse --abbrev-ref 'feature@{upstream}'
  [ "$status" -ne 0 ]
}

@test "add: a tag named like the remote-tracking ref does not stop the checkout" {
  # The branch exists only on the remote, so `gwa` tracks it. `origin/feature`
  # is a name a tag can take, and git refuses an ambiguous one outright.
  git checkout -qb feature
  commit_file theirs.txt yes "Their work"
  git push -q origin feature
  git checkout -q main
  git branch -D feature
  git tag origin/feature main

  origin_cli gwa feature
  [ "$status" -eq 0 ]
  [ "$(git -C "$output" rev-parse --abbrev-ref HEAD)" = "feature" ]
  [ "$(git config --get branch.feature.merge)" = "refs/heads/feature" ]
  [[ "$stderr" == *"(tracking origin/feature)"* ]]
}

@test "add: a slash in the branch name nests" {
  origin_cli gwa fix/login
  [ "$output" = "${WORKTREES}/fix/login/proj" ]
}

@test "add: stdout is the path and nothing else" {
  origin_cli gwa feature
  [ "$output" = "${WORKTREES}/feature/proj" ]
  [ -n "$stderr" ]
}

@test "add: --quiet stops the commentary" {
  origin_cli gwa feature --quiet
  [ "$output" = "${WORKTREES}/feature/proj" ]
  [[ "$stderr" != *"Fetching"* ]]
}

@test "add: an existing branch is checked out rather than refused" {
  git branch already-here
  origin_cli gwa already-here
  [ "$status" -eq 0 ]
  [ "$(git -C "$output" rev-parse --abbrev-ref HEAD)" = "already-here" ]
}

@test "add: asking twice gives the same path back" {
  origin_cli gwa feature
  local first="$output"
  origin_cli gwa feature
  [ "$output" = "$first" ]
  [[ "$stderr" == *"already has a worktree"* ]]
}

@test "add: every spelling reaches the same command" {
  origin_cli git-worktree add one
  [ "$status" -eq 0 ]
  origin_cli gw add two
  [ "$status" -eq 0 ]
  origin_cli gwa three
  [ "$status" -eq 0 ]
  [ -d "${WORKTREES}/one/proj" ] && [ -d "${WORKTREES}/two/proj" ] && [ -d "${WORKTREES}/three/proj" ]
}

@test "add: a dry run creates nothing" {
  origin_cli gwa feature --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/feature/proj" ]
  [[ "$stderr" == *"would run: git worktree add"* ]]
}

@test "add: an unusable branch name is refused" {
  origin_cli gwa "not a branch"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not a valid branch name"* ]]
}

@test "add: a flag with its value missing is refused, not a bash crash" {
  origin_cli gwa feature --path
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--path needs a value"* ]]
  [[ "$stderr" != *"unbound variable"* ]]

  origin_cli gwa feature --base
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--base needs a value"* ]]
}

@test "add: --base is what the success line names" {
  git tag v1
  commit_file later.txt yes "Later work"
  origin_cli gwa from-tag --base v1
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"(from v1)"* ]]
  [ "$(git -C "$output" rev-parse HEAD)" = "$(git rev-parse v1^{commit})" ]
}

@test "add: an existing branch is not described as coming from anywhere" {
  git branch already-here
  origin_cli gwa already-here
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"(from "* ]]
}

@test "add: a dry run does not fetch, and prunes nothing" {
  # A remote-tracking ref for a branch the remote does not have: `git fetch
  # --prune` deletes it, and a dry run must not.
  git update-ref refs/remotes/origin/ghost "$(git rev-parse HEAD)"

  origin_cli gwa feature --dry-run
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"would run: git fetch"* ]]
  [[ "$stderr" != *"Fetching"* ]]
  git show-ref --verify --quiet refs/remotes/origin/ghost
}

# --- the guard: three positions, one question ------------------------------

@test "guard A': a destination owned by another repository is named and refused" {
  local other
  other="$(sibling_repo other)"
  git -C "$other" worktree add -q -b theirs "${ROOT}/squatted"

  origin_cli gwa mine --path "${ROOT}/squatted"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"belongs to another repository"* ]]
  [[ "$stderr" == *"other/.git"* ]]
}

@test "guard B: a destination inside another repository's checkout is refused" {
  local other
  other="$(sibling_repo other)"
  git -C "$other" worktree add -q -b theirs "${ROOT}/squatted"

  origin_cli gwa mine --path "${ROOT}/squatted/nested"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"belongs to another repository"* ]]
  [ ! -d "${ROOT}/squatted/nested" ]
}

@test "guard B: git alone still allows it, so the guard cannot become decoration" {
  local other
  other="$(sibling_repo other)"
  git -C "$other" worktree add -q -b theirs "${ROOT}/squatted"

  run git worktree add -b raw "${ROOT}/squatted/raw-nested"
  [ "$status" -eq 0 ]
  [ -d "${ROOT}/squatted/raw-nested" ]
}

@test "guard C: a non-empty directory in the way is refused" {
  mkdir -p "${WORKTREES}/feature/proj"
  printf 'x\n' >"${WORKTREES}/feature/proj/stray"

  origin_cli gwa feature
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already exists and is not empty"* ]]
}

@test "guard: our own worktree at the destination is not a squatter" {
  origin_cli gwa feature
  local path="$output"
  origin_cli gwa feature --path "$path"
  [ "$status" -eq 0 ]
  [ "$output" = "$path" ]
}

@test "guard: the walk stops at the worktree root" {
  # The parent directory is itself a repository; an unbounded walk upward
  # would find it and refuse every destination.
  git init -q -b main "$ROOT"
  origin_cli gwa feature
  [ "$status" -eq 0 ]
  [ -d "${WORKTREES}/feature/proj" ]
}

# --- list ------------------------------------------------------------------

@test "list: JSON carries the absolute path" {
  origin_cli gwa feature
  origin_cli gwl --json
  run jq_of "$output" '.[] | select(.branch == "feature") | .path'
  [ "$output" = "${WORKTREES}/feature/proj" ]
}

@test "list: marks the worktree you are standing in" {
  origin_cli gwa feature
  origin_cli gwl --json
  run jq_of "$output" '.[] | select(.current) | .branch'
  [ "$output" = "main" ]
}

@test "list: counts drift from the head branch" {
  origin_cli gwa feature
  cd "${WORKTREES}/feature/proj"
  commit_file drift.txt yes "One ahead"
  cd "$REPO"
  origin_cli gwl --json
  run jq_of "$output" '.[] | select(.branch == "feature") | "\(.ahead)/\(.behind)"'
  [ "$output" = "1/0" ]
}

# --- remove ----------------------------------------------------------------

@test "remove: a squash-merged branch goes, and says how to bring it back" {
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  local sha
  sha="$(git rev-parse --short finished)"
  squash_merge_branch finished

  origin_cli gwr finished --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/finished" ]
  run git show-ref --verify --quiet refs/heads/finished
  [ "$status" -ne 0 ]
}

@test "remove: the recovery line is exactly runnable" {
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  local before
  before="$(git rev-parse finished)"
  squash_merge_branch finished

  origin_cli gwr finished --yes
  local line
  line="$(printf '%s\n' "$stderr" | grep 'restore: ' | sed 's/.*restore: //')"
  [ -n "$line" ]
  eval "$line"
  [ "$(git rev-parse finished)" = "$before" ]
}

@test "remove: a tag sharing the branch's name does not finish it" {
  origin_cli gwa unfinished
  cd "${WORKTREES}/unfinished/proj"
  commit_file wip.txt yes "Not done"
  cd "$REPO"
  # Read for the branch, this says the work is already on main.
  git tag unfinished main

  origin_cli gwr unfinished --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is not merged"* ]]
  [ -d "${WORKTREES}/unfinished/proj" ]
  git show-ref --verify --quiet refs/heads/unfinished
}

@test "remove: the recovery line names the branch and not a tag beside it" {
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  local before
  before="$(git rev-parse refs/heads/finished)"
  squash_merge_branch finished
  # A tag of the same name, on a different commit.
  git tag finished main

  origin_cli gwr finished --yes
  [ "$status" -eq 0 ]
  # `run` overwrites $stderr, so the line comes out of it first.
  local line
  line="$(printf '%s\n' "$stderr" | grep 'restore: ' | sed 's/.*restore: //')"
  [ -n "$line" ]

  run git show-ref --verify --quiet refs/heads/finished
  [ "$status" -ne 0 ]

  eval "$line"
  [ "$(git rev-parse refs/heads/finished)" = "$before" ]
}

@test "remove: an unmerged branch keeps its worktree as well as its branch" {
  origin_cli gwa unfinished
  cd "${WORKTREES}/unfinished/proj"
  commit_file wip.txt yes "Not done"
  cd "$REPO"

  origin_cli gwr unfinished --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is not merged"* ]]
  [ -d "${WORKTREES}/unfinished/proj" ]
  git show-ref --verify --quiet refs/heads/unfinished
}

@test "remove: --force takes the checkout and never the branch" {
  origin_cli gwa unfinished
  cd "${WORKTREES}/unfinished/proj"
  commit_file wip.txt yes "Not done"
  cd "$REPO"

  origin_cli gwr unfinished --yes --force
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/unfinished/proj" ]
  git show-ref --verify --quiet refs/heads/unfinished
  [[ "$stderr" == *"kept branch unfinished"* ]]
}

@test "remove: uncommitted work is refused" {
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  squash_merge_branch finished
  printf 'scratch\n' >"${WORKTREES}/finished/proj/scratch.txt"

  origin_cli gwr finished --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"uncommitted changes"* ]]
  [ -d "${WORKTREES}/finished/proj" ]
}

@test "remove: --force does not override uncommitted work" {
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  squash_merge_branch finished
  printf 'important\n' >"${WORKTREES}/finished/proj/important.txt"
  git -C "${WORKTREES}/finished/proj" add important.txt

  origin_cli gwr finished --yes --force
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"uncommitted changes"* ]]
  # The file, the checkout and the branch are all still here.
  [ -f "${WORKTREES}/finished/proj/important.txt" ]
  git show-ref --verify --quiet refs/heads/finished
}

@test "remove: --force keeps the branch even when it is merged" {
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  squash_merge_branch finished

  origin_cli gwr finished --yes --force
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/finished/proj" ]
  git show-ref --verify --quiet refs/heads/finished
  [[ "$stderr" == *"kept branch finished"* ]]
}

# --- the head branch -------------------------------------------------------

@test "remove: a worktree holding the head branch goes, and the branch stays" {
  # The main checkout has to be somewhere else before git will check main out
  # a second time, which is the ordinary shape: work in the clone, keep the
  # head branch in a worktree of its own.
  git checkout -q -b side
  origin_cli gwa main
  [ "$status" -eq 0 ]

  origin_cli gwr main --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/main/proj" ]
  git show-ref --verify --quiet refs/heads/main
  [[ "$stderr" == *"branch main stays; it is the head branch"* ]]
  [[ "$stderr" == *"kept branch main"* ]]
}

@test "remove: the head branch is never offered a restore line" {
  git checkout -q -b side
  origin_cli gwa main

  origin_cli gwr main --yes --quiet
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"This will delete:"* ]]
  [[ "$stderr" != *"restore"* ]]
}

@test "remove: the head branch is whichever git-worktree-plugin.headBranch names" {
  git checkout -q -b release
  git push -q origin release
  git checkout -q main
  git config git-worktree-plugin.headBranch release
  origin_cli gwa release
  [ "$status" -eq 0 ]

  origin_cli gwr release --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/release/proj" ]
  git show-ref --verify --quiet refs/heads/release
}

@test "remove: a head branch written as a remote ref is still the head branch" {
  git checkout -q -b side
  origin_cli gwa main
  git config git-worktree-plugin.headBranch origin/main

  origin_cli gwr main --yes
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/main
  [[ "$stderr" == *"branch main stays; it is the head branch"* ]]
}

@test "remove: a head branch written as a full ref is still the head branch" {
  git checkout -q -b side
  origin_cli gwa main
  git config git-worktree-plugin.headBranch refs/heads/main

  origin_cli gwr main --yes
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/main
  [[ "$stderr" == *"branch main stays; it is the head branch"* ]]
}

@test "remove: a head branch with a slash in its name is matched whole" {
  # Never pushed, so the head ref is the bare branch name: a guard that cut the
  # name at its first slash would compare against '2.x' and miss.
  git checkout -q -b release/2.x
  git checkout -q main
  git config git-worktree-plugin.headBranch release/2.x
  origin_cli gwa release/2.x
  [ "$status" -eq 0 ]

  origin_cli gwr release/2.x --yes
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/release/2.x
}

@test "remove: a merged branch whose name ends the head ref is still deleted" {
  # 'ain' is a suffix of 'origin/main'. Only an exact comparison tells the two
  # apart, and this branch is not the head branch.
  origin_cli gwa ain
  cd "${WORKTREES}/ain/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  squash_merge_branch ain

  origin_cli gwr ain --yes
  [ "$status" -eq 0 ]
  run git show-ref --verify --quiet refs/heads/ain
  [ "$status" -ne 0 ]
}

@test "remove: the head branch is kept in a repository with no remote" {
  git remote remove origin
  git checkout -q -b side
  origin_cli gwa main
  [ "$status" -eq 0 ]

  origin_cli gwr main --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/main/proj" ]
  git show-ref --verify --quiet refs/heads/main
}

# --- a detached worktree ---------------------------------------------------

@test "remove: a detached worktree goes when a ref already reaches its commit" {
  git worktree add -q --detach "${ROOT}/look" HEAD

  origin_cli gwr "${ROOT}/look" --yes
  [ "$status" -eq 0 ]
  [ ! -d "${ROOT}/look" ]
  [[ "$stderr" == *"stays; refs/heads/main reaches it"* ]]
}

@test "remove: a detached worktree at a commit no ref reaches is refused" {
  git worktree add -q --detach "${ROOT}/orphan" HEAD
  git -C "${ROOT}/orphan" commit -q --allow-empty -m "Only here"
  local sha
  sha="$(git -C "${ROOT}/orphan" rev-parse --short HEAD)"

  origin_cli gwr "${ROOT}/orphan" --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no ref reaches ${sha}"* ]]
  [[ "$stderr" == *"git branch <name> ${sha}"* ]]
  [ -d "${ROOT}/orphan" ]
}

@test "remove: --force takes an unreached detached worktree, and the undo is runnable" {
  git worktree add -q --detach "${ROOT}/orphan" HEAD
  git -C "${ROOT}/orphan" commit -q --allow-empty -m "Only here"
  local sha
  sha="$(git -C "${ROOT}/orphan" rev-parse --short HEAD)"

  origin_cli gwr "${ROOT}/orphan" --yes --force
  [ "$status" -eq 0 ]
  [ ! -d "${ROOT}/orphan" ]

  local line
  line="$(printf '%s\n' "$stderr" | grep 'restore with: git worktree add' | sed 's/.*restore with: //')"
  [ -n "$line" ]
  eval "$line"
  [ "$(git -C "${ROOT}/orphan" rev-parse --short HEAD)" = "$sha" ]
}

@test "remove: a path this repository has no worktree at is named as such" {
  origin_cli gwr "${ROOT}/nowhere" --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is not a worktree of this repository"* ]]
}

@test "remove: a closed pull request finishes the checkout, and the branch stays" {
  stub_forge https://github.com/owner/repo.git
  origin_cli gwa abandoned
  cd "${WORKTREES}/abandoned/proj"
  commit_file wip.txt yes "Went nowhere"
  cd "$REPO"
  stub_json pr-list.json <<'JSON'
[{ "number": 3, "headRefName": "abandoned", "state": "CLOSED" }]
JSON

  origin_cli gwr abandoned --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/abandoned/proj" ]
  [[ "$stderr" == *"pull request #3 is closed"* ]]
  [[ "$stderr" == *"kept branch abandoned"* ]]
  git show-ref --verify --quiet refs/heads/abandoned
}

@test "remove: a merged pull request git cannot see finishes the checkout, not the branch" {
  # The forge says merged; this clone has no commit to prove it. The checkout
  # goes, the branch stays, because only the content comparison can say that
  # deleting it loses nothing.
  stub_forge https://github.com/owner/repo.git
  origin_cli gwa landed
  cd "${WORKTREES}/landed/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  stub_json pr-list.json <<'JSON'
[{ "number": 5, "headRefName": "landed", "state": "MERGED" }]
JSON

  origin_cli gwr landed --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/landed/proj" ]
  git show-ref --verify --quiet refs/heads/landed
  [[ "$stderr" == *"kept branch landed"* ]]
}

@test "remove: --no-forge leaves the decision to git alone" {
  stub_forge https://github.com/owner/repo.git
  origin_cli gwa abandoned
  cd "${WORKTREES}/abandoned/proj"
  commit_file wip.txt yes "Went nowhere"
  cd "$REPO"
  stub_json pr-list.json <<'JSON'
[{ "number": 3, "headRefName": "abandoned", "state": "CLOSED" }]
JSON

  origin_cli gwr abandoned --yes --no-forge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is not merged"* ]]
  [ -d "${WORKTREES}/abandoned/proj" ]
}

# --- what is about to be deleted, and who may answer for it ----------------

@test "remove: says what it will delete, even under --yes and --quiet" {
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  local sha
  sha="$(git rev-parse --short finished)"
  squash_merge_branch finished

  origin_cli gwr finished --yes --quiet
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"This will delete:"* ]]
  [[ "$stderr" == *"the worktree at"* ]]
  [[ "$stderr" == *"branch finished (${sha})"* ]]
  [[ "$stderr" == *"restore with: git branch finished ${sha}"* ]]
}

@test "remove: ignored files are named, and --yes does not answer for them" {
  printf '.env\n' >.gitignore
  git add .gitignore
  git commit -qm "Ignore .env"
  git push -q origin main
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  squash_merge_branch finished
  printf 'SECRET=hunter2\n' >"${WORKTREES}/finished/proj/.env"

  origin_cli gwr finished --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *".env"* ]]
  [[ "$stderr" == *"nothing tracks and nothing restores"* ]]
  [[ "$stderr" == *"--yes does not answer that"* ]]
  [[ "$stderr" == *"--delete-ignored"* ]]
  # Nothing went: not the file, not the checkout, not the branch.
  [ -f "${WORKTREES}/finished/proj/.env" ]
  git show-ref --verify --quiet refs/heads/finished
}

@test "remove: --delete-ignored is the way through, typed on purpose" {
  printf '.env\n' >.gitignore
  git add .gitignore
  git commit -qm "Ignore .env"
  git push -q origin main
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  squash_merge_branch finished
  printf 'SECRET=hunter2\n' >"${WORKTREES}/finished/proj/.env"

  origin_cli gwr finished --yes --delete-ignored
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/finished/proj" ]
  # It still said what it was taking.
  [[ "$stderr" == *".env"* ]]
}

@test "remove: with no argument it says which worktree it needs" {
  origin_cli gwr --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"which worktree?"* ]]
}

@test "remove: a stash on the branch is refused" {
  origin_cli gwa finished
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  printf 'parked\n' >>README.md
  git stash push -q -m "parked"
  cd "$REPO"
  squash_merge_branch finished

  origin_cli gwr finished --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stash"* ]]
}

@test "remove: the current worktree and the main worktree are refused" {
  origin_cli gwr main --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"main worktree"* ]]
}

@test "remove: takes a path as well as a branch" {
  origin_cli gwa finished
  local path="$output"
  cd "${WORKTREES}/finished/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  squash_merge_branch finished

  origin_cli gwr "$path" --yes
  [ "$status" -eq 0 ]
  [ ! -d "$path" ]
}

@test "remove: an empty parent directory goes, the root stays" {
  origin_cli gwa fix/login
  cd "${WORKTREES}/fix/login/proj"
  commit_file done.txt yes "The work"
  cd "$REPO"
  squash_merge_branch fix/login

  origin_cli gwr fix/login --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/fix" ]
  [ -d "$WORKTREES" ]
}

@test "a repository with no remote still works" {
  git remote remove origin
  origin_cli gwa local-only
  [ "$status" -eq 0 ]
  origin_cli gwl --json
  run jq_of "$output" '[.[].branch] | join(",")'
  [ "$output" = "main,local-only" ]
}

@test "path: prints the worktree that has the branch" {
  origin_cli gwa feature
  origin_cli worktree path feature
  [ "$status" -eq 0 ]
  [ "$output" = "${WORKTREES}/feature/proj" ]
}

@test "path: stdout is one line, so a shell function can cd to it" {
  origin_cli gwa feature
  origin_cli worktree path feature
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 1 ]
  [ -d "$output" ]
}

@test "path: a slash in the branch name nests" {
  origin_cli gwa fix/login
  origin_cli worktree path fix/login
  [ "$output" = "${WORKTREES}/fix/login/proj" ]
}

@test "path: a branch with no worktree exits 1 and says which" {
  git branch nowt main
  origin_cli worktree path nowt
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"no worktree of this repository has nowt"* ]]
}

@test "path: a branch that does not exist exits 1 with nothing on stdout" {
  origin_cli worktree path never-existed
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "path: naming no branch, or two, is an error" {
  origin_cli worktree path
  [ "$status" -eq 1 ]
  origin_cli gwa feature
  origin_cli worktree path feature main
  [ "$status" -eq 1 ]
}

@test "path: gw path and gwp are the same command" {
  origin_cli gwa feature
  origin_cli gw path feature
  local via_gw="$output"
  origin_cli gwp feature
  [ "$output" = "$via_gw" ]
  [ "$output" = "${WORKTREES}/feature/proj" ]
}

# Nine worktrees, because the crash this guards against only starts when the
# match sits far enough down the records that worktree_records is still writing
# when awk exits. Every other worktree test makes at most three and asks about
# the one it just made, which is always the last record - so the suite could
# not see it.
@test "every branch answers, however many worktrees there are" {
  local b
  for b in one two three four five six seven eight; do
    origin_cli gwa "$b"
    [ "$status" -eq 0 ]
  done

  for b in one two three four five six seven eight; do
    origin_cli worktree path "$b"
    [ "$status" -eq 0 ]
    [ "$output" = "${WORKTREES}/${b}/proj" ]

    origin_cli gwa "$b"
    [ "$status" -eq 0 ]
    [ "$output" = "${WORKTREES}/${b}/proj" ]
  done
}

# Eight, and every one asked about. `worktree_record_at` reads the record list
# the same way `worktree_path_of_branch` does, and the failure that shape used
# to carry only showed when at least three records followed the match. Git
# lists linked worktrees sorted by directory name rather than by creation
# order, so the one just made is not the last one.
many_worktrees() {
  local branch
  for branch in "$@"; do
    origin_cli gwa "$branch"
    [ "$status" -eq 0 ]
  done
}

@test "remove: a worktree is recognised wherever it sits in the list" {
  many_worktrees h8 g7 f6 e5 d4 c3 b2 a1

  local branch
  for branch in h8 g7 f6 e5 d4 c3 b2 a1; do
    (
      cd "${WORKTREES}/${branch}/proj" || exit 1
      commit_file work.txt yes "Work on ${branch}"
    )
  done

  # Unmerged, so each refuses and says why. The failure this covers exits 141
  # with both streams empty.
  for branch in h8 g7 f6 e5 d4 c3 b2 a1; do
    origin_cli gwr "$branch"
    [ "$status" -eq 1 ]
    [ -n "${output}${stderr}" ]
    [[ "${output}${stderr}" == *"${branch}"* ]]
  done
}

@test "list: many worktrees are all reported, with their branches" {
  many_worktrees h8 g7 f6 e5 d4 c3 b2 a1

  origin_cli gwl --json
  [ "$status" -eq 0 ]
  run jq_of "$output" 'length'
  [ "$output" = 9 ]

  origin_cli gwl --json
  run jq_of "$output" '[.[].branch] | sort | join(",")'
  [ "$output" = "a1,b2,c3,d4,e5,f6,g7,h8,main" ]
}

@test "list: age and dirty state survive the shared commit lookup" {
  many_worktrees b2 a1
  printf 'scratch\n' >"${WORKTREES}/a1/proj/untracked.txt"

  origin_cli gwl --json
  [ "$status" -eq 0 ]
  run jq_of "$output" '.[] | select(.branch == "a1") | .dirty'
  [ "$output" = true ]

  origin_cli gwl --json
  run jq_of "$output" '.[] | select(.branch == "b2") | .dirty'
  [ "$output" = false ]

  # Every worktree here sits on the same commit, which is what the cache keys
  # on: all of them still carry that commit's date and age.
  origin_cli gwl --json
  run jq_of "$output" '[.[] | select(.lastCommit == "" or .age == "")] | length'
  [ "$output" = 0 ]
}

# The key is set after the worktree exists, because `gwa` branches from the
# head branch and a name resolving to nothing has nothing to branch from. The
# work is a real file: an empty commit reaches the head branch and is finished.
@test "remove: a refusal under a misstated head branch names the config key" {
  origin_cli gwa feature
  cd "${WORKTREES}/feature/proj"
  commit_file work.txt yes "The work"
  cd "$REPO"
  git config git-worktree-plugin.headBranch does-not-exist

  origin_cli gwr feature
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"git-worktree-plugin.headBranch names does-not-exist"* ]]
  [[ "$stderr" == *"no branch here or on origin"* ]]
  [[ "$stderr" == *"origin doctor"* ]]
}

@test "remove: a refusal under a working head branch says nothing about the key" {
  origin_cli gwa feature
  cd "${WORKTREES}/feature/proj"
  commit_file work.txt yes "The work"
  cd "$REPO"

  origin_cli gwr feature
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"feature is not merged into origin/main"* ]]
  [[ "$stderr" != *"git-worktree-plugin.headBranch"* ]]
}

# --------------------------------------------------------------------------
# move
# --------------------------------------------------------------------------
#
# Directory name equals branch name is the invariant `gwl` and `gwr` both read,
# so every one of these checks both halves, never just the rename.

@test "move: renames the branch and moves the checkout together" {
  origin_cli gwa old-name
  cd "${WORKTREES}/old-name/proj"

  origin_cli gwm new-name --yes
  [ "$status" -eq 0 ]
  [ "$output" = "${WORKTREES}/new-name/proj" ]
  [ -d "${WORKTREES}/new-name/proj" ]
  [ ! -d "${WORKTREES}/old-name/proj" ]
  [ "$(git -C "${WORKTREES}/new-name/proj" rev-parse --abbrev-ref HEAD)" = "new-name" ]
  run git show-ref --verify --quiet refs/heads/old-name
  [ "$status" -ne 0 ]
}

@test "move: the empty parent a nested name leaves behind goes, the root stays" {
  origin_cli gwa fix/login
  cd "${WORKTREES}/fix/login/proj"

  origin_cli gwm renamed --yes
  [ "$status" -eq 0 ]
  [ ! -d "${WORKTREES}/fix" ]
  [ -d "$WORKTREES" ]
}

@test "move: a nested new name gets its parent made for it" {
  origin_cli gwa flat
  cd "${WORKTREES}/flat/proj"

  origin_cli gwm fix/login --yes
  [ "$status" -eq 0 ]
  [ -d "${WORKTREES}/fix/login/proj" ]
  [ "$(git -C "${WORKTREES}/fix/login/proj" rev-parse --abbrev-ref HEAD)" = "fix/login" ]
}

@test "move: the main worktree is refused" {
  origin_cli gwm something --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"main worktree"* ]]
}

@test "move: a name already taken by a branch is refused" {
  origin_cli gwa one
  git branch taken main
  cd "${WORKTREES}/one/proj"

  origin_cli gwm taken --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already exists"* ]]
  [ -d "${WORKTREES}/one/proj" ]
}

@test "move: renaming to the name it already has is refused" {
  origin_cli gwa same
  cd "${WORKTREES}/same/proj"

  origin_cli gwm same --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"already called that"* ]]
}

@test "move: a destination another worktree already holds is refused" {
  origin_cli gwa one
  origin_cli gwa two
  cd "${WORKTREES}/one/proj"

  origin_cli gwm two --yes
  [ "$status" -eq 1 ]
  [ -d "${WORKTREES}/one/proj" ]
  [ -d "${WORKTREES}/two/proj" ]
}

@test "move: an invalid branch name is refused before anything moves" {
  origin_cli gwa one
  cd "${WORKTREES}/one/proj"

  origin_cli gwm 'not a branch' --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not a valid branch name"* ]]
  [ -d "${WORKTREES}/one/proj" ]
}

@test "move: with no name it says which it needs" {
  origin_cli gwa one
  cd "${WORKTREES}/one/proj"

  origin_cli gwm
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"which name"* ]]
}

@test "move: two names is an error, not a guess" {
  origin_cli gwa one
  cd "${WORKTREES}/one/proj"

  origin_cli gwm alpha beta
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"one branch name, not two"* ]]
}

@test "move: a detached worktree has no branch to rename" {
  origin_cli gwa one
  cd "${WORKTREES}/one/proj"
  git checkout -q --detach

  origin_cli gwm renamed --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no branch checked out"* ]]
}

@test "move: a locked worktree is refused, and names the unlock" {
  origin_cli gwa one
  git worktree lock "${WORKTREES}/one/proj"
  cd "${WORKTREES}/one/proj"

  origin_cli gwm renamed --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is locked"* ]]
  [[ "$stderr" == *"worktree unlock"* ]]
}

@test "move: gw move and gwm are the same command" {
  origin_cli gwa one
  cd "${WORKTREES}/one/proj"

  origin_cli gw move renamed --yes
  [ "$status" -eq 0 ]
  [ "$output" = "${WORKTREES}/renamed/proj" ]
}

@test "move: what it moved is what gwl then reports" {
  origin_cli gwa old-name
  cd "${WORKTREES}/old-name/proj"
  origin_cli gwm new-name --yes
  cd "$REPO"

  origin_cli gwl --json
  run jq_of "$output" '[.[].branch] | sort | join(",")'
  [ "$output" = "main,new-name" ]
}

@test "move: a dry run moves nothing" {
  origin_cli gwa one
  cd "${WORKTREES}/one/proj"

  origin_cli gwm renamed --dry-run
  [ "$status" -eq 0 ]
  [ -d "${WORKTREES}/one/proj" ]
  [ ! -d "${WORKTREES}/renamed/proj" ]
  run git show-ref --verify --quiet refs/heads/one
  [ "$status" -eq 0 ]
}
