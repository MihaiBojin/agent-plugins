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
