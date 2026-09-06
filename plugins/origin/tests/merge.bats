#!/usr/bin/env bats
#
# Merging: the refusals, the material, and the trailers that have to survive
# whatever anybody writes over them.

load helpers/repo

setup() {
  setup_repo
  stub_forge https://github.com/owner/repo.git
  stub_json repo.json <<'JSON'
{ "viewerDefaultMergeMethod": "SQUASH", "squashMergeAllowed": true, "mergeCommitAllowed": true, "rebaseMergeAllowed": true }
JSON

  git checkout -qb feature
  commit_file loader.txt one "Rewrite the loader"
  git commit -q --allow-empty -m "wip"
  git commit -q --allow-empty -m "$(printf 'Handle the empty case\n\nCo-authored-by: Ada Lovelace <ada@example.invalid>')"
  git push -q -u origin feature

  pr_json '"state": "OPEN", "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN", "statusCheckRollup": []'
}

# The canned pull request with a different description.
pr_json_body() {
  stub_json pr.json <<JSON
{
  "number": 7,
  "title": "Rewrite the loader",
  "body": $(printf '%s' "$1" | jq -Rs .),
  "url": "https://github.com/owner/repo/pull/7",
  "author": { "login": "someone" },
  "baseRefName": "main",
  "headRefName": "feature",
  "state": "OPEN", "isDraft": false, "mergeable": "MERGEABLE",
  "mergeStateStatus": "CLEAN", "statusCheckRollup": []
}
JSON
}

# The canned pull request, with whatever the test wants to vary spliced in.
pr_json() {
  stub_json pr.json <<JSON
{
  "number": 7,
  "title": "Rewrite the loader",
  "body": "The old one read the whole file. Fixes #12",
  "url": "https://github.com/owner/repo/pull/7",
  "author": { "login": "someone" },
  "baseRefName": "main",
  "headRefName": "feature",
  ${1}
}
JSON
}

@test "gather brings back the commits, the diffstat and the trailers" {
  origin_cli merge --gather
  [ "$status" -eq 0 ]

  run jq_of "$output" '.pr.number, (.commits | length), .diffstat.files'
  [ "${lines[0]}" = "7" ]
  [ "${lines[1]}" = "3" ]
  [ "${lines[2]}" = "1" ]
}

@test "gather finds the issue and the co-author wherever they were written" {
  origin_cli merge --gather
  run jq_of "$output" '.trailers.issues[0], .trailers.coAuthors[0]'
  [[ "${lines[0]}" == "Fixes #12" ]]
  [[ "${lines[1]}" == "Ada Lovelace <ada@example.invalid>" ]]
}

@test "a co-author written in prose is not a co-author" {
  git commit -q --allow-empty -m "$(printf 'Explain the convention\n\nThe docs say Co-authored-by: Nobody <no@one> as an example of a trailer.')"
  git push -q origin feature

  origin_cli merge --gather
  run jq_of "$output" '.trailers.coAuthors | join(",")'
  [[ "$output" == *"Ada Lovelace"* ]]
  [[ "$output" != *"Nobody"* ]]
}

@test "a closing keyword inside backticks closes nothing" {
  pr_json_body 'Explains the convention: `Fixes #999` is how you close an issue. Fixes #12'
  origin_cli merge --gather
  run jq_of "$output" '.trailers.issues | join(",")'
  [ "$output" = "Fixes #12" ]
}

@test "a closing keyword inside a fenced block closes nothing" {
  pr_json_body "$(printf 'Real text.\n\n```\nFixes #999\n```\n')"
  origin_cli merge --gather
  run jq_of "$output" '.trailers.issues | length'
  [ "$output" = "0" ]
}

@test "a draft is refused, and says so" {
  pr_json '"state": "OPEN", "isDraft": true, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN", "statusCheckRollup": []'
  origin_cli merge --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"it is a draft"* ]]
  [[ "$stderr" == *"pass --force"* ]]
}

@test "a failing check is refused by name" {
  pr_json '"state": "OPEN", "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN",
    "statusCheckRollup": [
      { "name": "build", "conclusion": "SUCCESS" },
      { "name": "lint", "conclusion": "FAILURE" }
    ]'
  origin_cli merge --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"these checks are failing: lint"* ]]
  [[ "$stderr" != *"build"* ]]
}

@test "a check still running is refused by name" {
  pr_json '"state": "OPEN", "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "UNSTABLE",
    "statusCheckRollup": [
      { "name": "build", "status": "COMPLETED", "conclusion": "SUCCESS" },
      { "name": "e2e", "status": "IN_PROGRESS", "conclusion": null }
    ]'
  origin_cli merge --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"these checks have not finished: e2e"* ]]
  [[ "$stderr" != *"build"* ]]
  run grep_count "gh pr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "0" ]
}

@test "a commit status still pending is refused, and one that is expected too" {
  pr_json '"state": "OPEN", "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "UNSTABLE",
    "statusCheckRollup": [
      { "context": "ci/deploy", "state": "PENDING" },
      { "context": "ci/sign", "state": "EXPECTED" },
      { "context": "ci/unit", "state": "SUCCESS" }
    ]'
  origin_cli merge --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"these checks have not finished: ci/deploy, ci/sign"* ]]
  [[ "$stderr" != *"ci/unit"* ]]
}

@test "a check that failed is named once, as failing rather than as unfinished" {
  pr_json '"state": "OPEN", "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "UNSTABLE",
    "statusCheckRollup": [
      { "name": "lint", "status": "COMPLETED", "conclusion": "FAILURE" }
    ]'
  origin_cli merge --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"these checks are failing: lint"* ]]
  [[ "$stderr" != *"have not finished"* ]]
}

@test "--force merges past a check that has not finished" {
  pr_json '"state": "OPEN", "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "UNSTABLE",
    "statusCheckRollup": [ { "name": "e2e", "status": "QUEUED", "conclusion": null } ]'
  origin_cli merge --yes --force --body "Chunked reads."
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"have not finished: e2e"* ]]
  [[ "$stderr" == *"merging anyway"* ]]
}

@test "gather reports the unfinished checks without waiting for them" {
  pr_json '"state": "OPEN", "isDraft": false, "mergeable": "MERGEABLE", "mergeStateStatus": "UNSTABLE",
    "statusCheckRollup": [ { "name": "e2e", "status": "IN_PROGRESS", "conclusion": null } ]'
  origin_cli merge --gather
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" '.pr.pendingChecks | join(",")')" = "e2e" ]
  [[ "$(jq_of "$output" '.refusals | join("|")')" == *"have not finished: e2e"* ]]
}

@test "a conflict is refused" {
  pr_json '"state": "OPEN", "isDraft": false, "mergeable": "CONFLICTING", "mergeStateStatus": "DIRTY", "statusCheckRollup": []'
  origin_cli merge --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"conflicts with main"* ]]
}

@test "--force merges past a refusal, having said what it is overriding" {
  pr_json '"state": "OPEN", "isDraft": true, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN", "statusCheckRollup": []'
  origin_cli merge --yes --force
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"it is a draft"* ]]
  [[ "$stderr" == *"merging anyway"* ]]
  run grep_count "gh pr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "1" ]
}

@test "a pull request that is already merged is not merged again" {
  pr_json '"state": "MERGED", "isDraft": false, "mergeable": "UNKNOWN", "mergeStateStatus": "UNKNOWN", "statusCheckRollup": []'
  origin_cli merge --yes
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is MERGED"* ]]
  run grep_count "gh pr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "0" ]
}

@test "the trailers are put back into a body written without them" {
  origin_cli merge --yes --dry-run --body "Read the file in chunks instead of whole."
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Read the file in chunks instead of whole."* ]]
  [[ "$stderr" == *"Fixes #12"* ]]
  [[ "$stderr" == *"Co-authored-by: Ada Lovelace <ada@example.invalid>"* ]]
}

@test "a body that already carries a trailer does not get it twice" {
  origin_cli merge --yes --dry-run --body "$(printf 'Chunked reads.\n\nFixes #12')"
  count="$(printf '%s\n' "$stderr" | grep -c 'Fixes #12' || true)"
  [ "$count" = "1" ]
}

@test "a longer issue reference does not stand in for a shorter one" {
  # `Fixes #1` is a substring of `Fixes #12`. Reading the body for the shorter
  # one and finding the longer leaves issue 1 open, silently.
  pr_json_body 'Fixes #1 and Closes #2'
  origin_cli merge --yes --dry-run --body "$(printf 'Chunked reads.\n\nFixes #12 and Closes #25')"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Fixes #1"$'\n'* ]]
  [[ "$stderr" == *"Closes #2"$'\n'* ]]
}

@test "a trailer the body already carries is still recognised whatever its case" {
  pr_json_body 'Fixes #12'
  origin_cli merge --yes --dry-run --body "$(printf 'Chunked reads.\n\nfixes #12')"
  count="$(printf '%s\n' "$stderr" | grep -c -i 'fixes #12' || true)"
  [ "$count" = "1" ]
}

@test "the squash subject keeps GitHub's own convention" {
  origin_cli merge --yes --dry-run --body "Anything"
  [[ "$stderr" == *"Rewrite the loader (#7)"* ]]
}

@test "a dry run merges nothing" {
  origin_cli merge --yes --dry-run --body "Anything"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"would run: gh pr merge"* ]]
  run grep_count "gh pr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "0" ]
}

@test "merging leaves the remote branch where it is" {
  origin_cli merge --yes --body "Anything"
  [ "$status" -eq 0 ]
  git --git-dir="$UPSTREAM" show-ref --verify --quiet refs/heads/feature
  git show-ref --verify --quiet refs/remotes/origin/feature
  [[ "$stderr" != *"This will delete:"* ]]
}

@test "a pull request from a fork takes nothing of this repository with it" {
  # `headRefName` is the bare branch name, so a fork's `main` and this
  # repository's `main` are the same string, and a remote-tracking ref matching
  # the name is evidence of nothing.
  pr_json '"state": "OPEN", "isDraft": false, "isCrossRepository": true,
    "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN", "statusCheckRollup": []'

  origin_cli merge --yes --body "Anything"
  [ "$status" -eq 0 ]
  git --git-dir="$UPSTREAM" show-ref --verify --quiet refs/heads/feature
}

@test "a number that names a different pull request than it resolves to is refused" {
  # The canned pull request is #7. Asking for #9 must not merge #7.
  git checkout -q main
  origin_cli merge 9 --yes --body "Anything"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"#9"* ]]
  run grep_count "gh pr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "0" ]
}

@test "the range is read from the remote this repository belongs to" {
  git remote rename origin upstream
  git config git-worktree-plugin.remote upstream
  # A stale `origin` beside it, with the fork's own idea of both branches.
  git remote add origin "$UPSTREAM"
  git update-ref refs/remotes/origin/main "$(git rev-parse main)"
  git update-ref refs/remotes/origin/feature "$(git rev-parse main)"

  origin_cli merge --gather
  [ "$status" -eq 0 ]
  # Three commits, read from upstream/main..upstream/feature. Reading
  # origin/main..origin/feature would have found none.
  run jq_of "$output" '.commits | length'
  [ "$output" = "3" ]
}

@test "--no-delete-branch is refused, because nothing here deletes one" {
  origin_cli merge --yes --no-delete-branch --body "Anything"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--no-delete-branch is gone"* ]]
  run grep_count "gh pr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "0" ]
}

@test "the strategy defaults to what the repository prefers" {
  stub_json repo.json <<'JSON'
{ "viewerDefaultMergeMethod": "REBASE", "squashMergeAllowed": true, "mergeCommitAllowed": true, "rebaseMergeAllowed": true }
JSON
  origin_cli merge --yes --body "Anything"
  run grep -F "gh pr merge" "$ORIGIN_STUB_LOG"
  [[ "$output" == *"--rebase"* ]]
}

@test "a strategy the repository forbids is refused before the API is called" {
  stub_json repo.json <<'JSON'
{ "viewerDefaultMergeMethod": "SQUASH", "squashMergeAllowed": true, "mergeCommitAllowed": false, "rebaseMergeAllowed": false }
JSON
  origin_cli merge --yes --merge --body "Anything"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"does not allow a merge"* ]]
  run grep_count "gh pr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "0" ]
}

@test "the strategy asked for is the strategy passed on" {
  origin_cli merge --yes --rebase --body "Anything"
  run grep -F "gh pr merge" "$ORIGIN_STUB_LOG"
  [[ "$output" == *"--rebase"* ]]
  [[ "$output" != *"--squash"* ]]
}

@test "with no body written, the description and its trailers are the body" {
  origin_cli merge --yes --dry-run
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"The old one read the whole file."* ]]
}

@test "a pull request can be named by number instead of by branch" {
  git checkout -q main
  origin_cli merge 7 --yes --dry-run --body "Anything"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Rewrite the loader (#7)"* ]]
}

@test "GitLab gets one squash message, and no auto-merge" {
  stub_forge https://gitlab.example.com/group/project.git
  stub_json api.json <<'JSON'
{ "merge_method": "merge", "squash_option": "always" }
JSON
  stub_json mr.json <<'JSON'
{
  "iid": 4, "title": "Rewrite the loader", "description": "Fixes #12",
  "state": "opened", "web_url": "https://gitlab.example.com/group/project/-/merge_requests/4",
  "author": { "username": "someone" }, "draft": false,
  "target_branch": "main", "source_branch": "feature",
  "has_conflicts": false, "detailed_merge_status": "mergeable"
}
JSON

  origin_cli merge --yes --body "Chunked reads."
  [ "$status" -eq 0 ]
  run grep -F "glab mr merge" "$ORIGIN_STUB_LOG"
  [[ "$output" == *"--squash-message"* ]]
  [[ "$output" == *"--auto-merge=false"* ]]
  # No (#4): that decoration is GitHub's convention, not GitLab's.
  [[ "$output" != *"(#4)"* ]]
}

@test "a GitLab pipeline still running is refused" {
  stub_forge https://gitlab.example.com/group/project.git
  stub_json api.json <<'JSON'
{ "merge_method": "merge", "squash_option": "always" }
JSON
  stub_json mr.json <<'JSON'
{
  "iid": 4, "title": "Rewrite the loader", "description": "Fixes #12",
  "state": "opened", "web_url": "https://gitlab.example.com/group/project/-/merge_requests/4",
  "author": { "username": "someone" }, "draft": false,
  "target_branch": "main", "source_branch": "feature",
  "has_conflicts": false, "detailed_merge_status": "ci_still_running",
  "head_pipeline": { "status": "running" }
}
JSON

  origin_cli merge --yes --body "Chunked reads."
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"these checks have not finished: pipeline"* ]]
  run grep_count "glab mr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "0" ]
}

@test "a GitLab merge request waiting on CI it will not name is refused anyway" {
  stub_forge https://gitlab.example.com/group/project.git
  stub_json api.json <<'JSON'
{ "merge_method": "merge", "squash_option": "always" }
JSON
  stub_json mr.json <<'JSON'
{
  "iid": 4, "title": "Rewrite the loader", "description": "Fixes #12",
  "state": "opened", "web_url": "https://gitlab.example.com/group/project/-/merge_requests/4",
  "author": { "username": "someone" }, "draft": false,
  "target_branch": "main", "source_branch": "feature",
  "has_conflicts": false, "detailed_merge_status": "ci_still_running"
}
JSON

  origin_cli merge --yes --body "Chunked reads."
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"checks still running"* ]]
}

@test "--edit with nowhere to open an editor refuses rather than hangs" {
  origin_cli merge --yes --edit --body "Anything" </dev/null
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"needs a terminal"* ]]
}

@test "--yes merges without asking, and a body passed with it still wins" {
  # The slash command passes $ARGUMENTS straight through: the model asks the
  # question, because an agent session has no terminal to ask at. Here --yes
  # says nothing about which body is used.
  printf 'A body somebody wrote\n' >"${ROOT}/body.txt"

  origin_cli merge 7 --yes --body-file "${ROOT}/body.txt" --dry-run --verbose
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"A body somebody wrote"* ]]
}

@test "--yes is accepted alongside --gather, so \$ARGUMENTS passes through" {
  origin_cli merge 7 --yes --gather
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .pr.number)" = "7" ]
}

@test "--auto says what took its place instead of merging" {
  origin_cli merge 7 --auto --body "Anything"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--auto is gone"* ]]
  [[ "$stderr" == *"pass --yes"* ]]
  run grep_count "gh pr merge" "$ORIGIN_STUB_LOG"
  [ "$output" = "0" ]
}
