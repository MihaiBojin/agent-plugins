#!/usr/bin/env bats

load helpers/repo

setup() {
  setup_repo
  stub_forge https://github.com/owner/repo.git
  git switch -qc feature
  CI_HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  CI_BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  CI_MERGE=cccccccccccccccccccccccccccccccccccccccc
  export CI_HEAD CI_BASE CI_MERGE
  stub_json pr.json <<JSON
{"number":7,"url":"https://github.com/owner/repo/pull/7","state":"OPEN",
 "headRefName":"feature","baseRefName":"main","headRefOid":"$CI_HEAD",
 "headRepository":{"name":"repo"},"headRepositoryOwner":{"login":"fork"},
 "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
 "statusCheckRollup":[{"name":"tests","status":"COMPLETED","conclusion":"SUCCESS"}]}
JSON
  stub_json checks.json <<'JSON'
[{"name":"tests","state":"SUCCESS","bucket":"pass","link":"https://github.com/owner/repo/actions/runs/12/job/13"}]
JSON
}

gitlab_fixture() {
  stub_forge https://gitlab.com/team/repo.git
  stub_json mr.json <<JSON
{"iid":7,"web_url":"https://gitlab.com/team/repo/-/merge_requests/7","state":"opened",
 "source_branch":"feature","target_branch":"main","sha":"$CI_HEAD",
 "source_project_id":22,"target_project_id":11,"detailed_merge_status":"mergeable",
 "head_pipeline":{"id":90,"project_id":22,"sha":"$CI_HEAD","status":"success"}}
JSON
  stub_json pipeline.json <<JSON
{"id":90,"project_id":22,"sha":"$CI_HEAD","ref":"feature","status":"success",
 "web_url":"https://gitlab.com/fork/repo/-/pipelines/90"}
JSON
  stub_json jobs.json <<'JSON'
[{"id":91,"name":"tests","status":"success","web_url":"https://gitlab.com/fork/repo/-/jobs/91"}]
JSON
}

replace_json() {
  local file="$1" expression="$2"
  jq "$expression" "${ORIGIN_STUB_DIR}/${file}" >"${ORIGIN_STUB_DIR}/${file}.new"
  mv "${ORIGIN_STUB_DIR}/${file}.new" "${ORIGIN_STUB_DIR}/${file}"
}

@test "CI returns the source identity and check URL without changing git" {
  local before
  before="$(git rev-parse HEAD)"
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(jq_of "$output" .checksState)" = passed ]
  [ "$(jq_of "$output" .pr.headSha)" = "$CI_HEAD" ]
  [ "$(jq_of "$output" .pr.sourceProject)" = fork/repo ]
  [ "$(jq_of "$output" '.checks[0].link')" = https://github.com/owner/repo/actions/runs/12/job/13 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -z "$(git status --porcelain)" ]
  ! grep -E '^(gh|glab) (pr|mr|run|ci) (merge|rerun|retry|ready) ' "$ORIGIN_STUB_LOG"
}

@test "CI resolves the current branch and preserves forge repository context" {
  export GH_REPO=github.com/owner/repo
  origin_cli ci
  [ "$status" -eq 0 ]
  grep -q 'gh pr view feature' "$ORIGIN_STUB_LOG"
  [ "$(cat "$ORIGIN_STUB_DIR/gh-context")" = "$GH_REPO" ]
}

@test "CI reports pending checks despite gh exit 8" {
  replace_json checks.json '.[0].state = "IN_PROGRESS" | .[0].bucket = "pending"'
  export ORIGIN_STUB_GH_CHECKS_STATUS=8
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = pending ]
}

@test "CI reports failing checks despite gh exit 1" {
  replace_json checks.json '.[0].state = "FAILURE" | .[0].bucket = "fail"'
  export ORIGIN_STUB_GH_CHECKS_STATUS=1
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = failed ]
}

@test "an empty GitHub rollup is unknown and never calls checks" {
  replace_json pr.json '.statusCheckRollup = []'
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = unknown ]
  ! grep -q 'gh pr checks' "$ORIGIN_STUB_LOG"
}

@test "GitHub read errors and malformed checks produce no snapshot" {
  export ORIGIN_STUB_GH_CHECKS_STATUS=4
  origin_cli ci 7
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  unset ORIGIN_STUB_GH_CHECKS_STATUS
  stub_json checks.json <<<'{"message":"access denied"}'
  origin_cli ci 7
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "an unknown check conclusion does not become a pass" {
  replace_json checks.json '.[0].bucket = "new-state"'
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = unknown ]
}

@test "a new head during the check read invalidates the result" {
  jq --arg head "$CI_BASE" '.headRefOid = $head' "$ORIGIN_STUB_DIR/pr.json" >"$ORIGIN_STUB_DIR/pr-after.json"
  export ORIGIN_STUB_GH_VIEW_THEN=pr-after.json
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .stale)" = true ]
  [ "$(jq_of "$output" .checksState)" = unknown ]
  [ "$(jq_of "$output" .pr.headSha)" = "$CI_BASE" ]
}

@test "a retarget during the check read invalidates the result" {
  jq '.baseRefName = "release"' "$ORIGIN_STUB_DIR/pr.json" >"$ORIGIN_STUB_DIR/pr-after.json"
  export ORIGIN_STUB_GH_VIEW_THEN=pr-after.json
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .stale)" = true ]
}

@test "CI rejects a missing head SHA or a mismatched review number" {
  origin_cli ci 8
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  replace_json pr.json 'del(.headRefOid)'
  origin_cli ci 7
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "CI requires a number on detached HEAD and rejects malformed arguments" {
  git checkout -q --detach
  origin_cli ci
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"HEAD is detached"* ]]
  origin_cli ci 7 8
  [ "$status" -ne 0 ]
  origin_cli ci 7oops
  [ "$status" -ne 0 ]
}

@test "GitLab reads jobs from the MR pipeline project across all pages" {
  gitlab_fixture
  export GITLAB_REPO=https://gitlab.com/team/repo
  stub_json jobs.json <<'JSON'
[{"id":91,"name":"tests","status":"success"}]
[{"id":92,"name":"deploy","status":"failed"}]
JSON
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = failed ]
  [ "$(jq_of "$output" '.checks | length')" = 3 ]
  [ "$(jq_of "$output" .pipeline.project_id)" = 22 ]
  grep -q 'projects/22/pipelines/90/jobs?per_page=100 --paginate' "$ORIGIN_STUB_LOG"
  ! grep -q 'projects/11/pipelines' "$ORIGIN_STUB_LOG"
  [ "$(cat "$ORIGIN_STUB_DIR/glab-context")" = "$GITLAB_REPO" ]
}

@test "an incomplete second review read produces no snapshot" {
  stub_json pr-after.json <<<'{}'
  export ORIGIN_STUB_GH_VIEW_THEN=pr-after.json
  origin_cli ci 7
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "GitHub neutral and skipped checks retain their native states" {
  stub_json checks.json <<'JSON'
[{"name":"optional","state":"NEUTRAL","bucket":"pass"},
 {"name":"paths","state":"SKIPPED","bucket":"skipping"}]
JSON
  replace_json pr.json '.mergeStateStatus = "BLOCKED"'
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = passed ]
  [ "$(jq_of "$output" .pr.mergeStateStatus)" = BLOCKED ]
  [ "$(jq_of "$output" '.checks[0].state')" = NEUTRAL ]
}

@test "GitLab manual jobs block while allowed failures do not" {
  gitlab_fixture
  replace_json jobs.json '.[0].status = "manual"'
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = blocked ]
  replace_json jobs.json '.[0].allow_failure = true'
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = passed ]
}

@test "large GitLab job lists are read without shell argument limits" {
  gitlab_fixture
  jq -n '[range(0;800) | {id:.,name:(("job" + tostring) + ("x" * 200)),
    status:"success",runner:{description:("x" * 1000)}}]' >"$ORIGIN_STUB_DIR/jobs.json"
  origin_cli ci 7
  [ "$status" -eq 0 ]
  # Feed the result through stdin here too; the snapshot exceeds one argv slot.
  [ "$(printf '%s' "$output" | jq '.checks | length')" = 801 ]
}

@test "GitLab running pipeline remains pending even with successful jobs" {
  gitlab_fixture
  replace_json pipeline.json '.status = "running"'
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = pending ]
}

@test "a GitLab MR without a pipeline is unknown" {
  gitlab_fixture
  replace_json mr.json '.head_pipeline = null'
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = unknown ]
  ! grep -q 'glab api' "$ORIGIN_STUB_LOG"
}

@test "a stale GitLab source pipeline cannot report green" {
  gitlab_fixture
  replace_json pipeline.json ".sha = \"$CI_BASE\""
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .stale)" = true ]
  [ "$(jq_of "$output" .checksState)" = unknown ]
}

@test "a merged-result pipeline must contain the current source and target" {
  gitlab_fixture
  replace_json pipeline.json ".sha = \"$CI_MERGE\" | .ref = \"refs/merge-requests/7/merge\""
  stub_json pipeline-commit.json <<JSON
{"id":"$CI_MERGE","parent_ids":["$CI_HEAD","$CI_BASE"]}
JSON
  stub_json pipeline-base.json <<JSON
{"commit":{"id":"$CI_BASE"}}
JSON
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .checksState)" = passed ]
  [ "$(jq_of "$output" .pipeline.association)" = merge-result ]
  replace_json pipeline-base.json ".commit.id = \"$CI_MERGE\""
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .stale)" = true ]
}

@test "a changed MR pipeline during the read invalidates the result" {
  gitlab_fixture
  jq '.head_pipeline.id = 99' "$ORIGIN_STUB_DIR/mr.json" >"$ORIGIN_STUB_DIR/mr-after.json"
  export ORIGIN_STUB_GLAB_VIEW_THEN=mr-after.json
  origin_cli ci 7
  [ "$status" -eq 0 ]
  [ "$(jq_of "$output" .stale)" = true ]
}

@test "GitLab pipeline and job errors produce no snapshot" {
  gitlab_fixture
  replace_json pipeline.json '.id = 91'
  origin_cli ci 7
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  replace_json pipeline.json '.id = 90'
  stub_json jobs.json <<<'{"message":"forbidden"}'
  origin_cli ci 7
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
