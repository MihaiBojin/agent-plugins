# shellcheck shell=bash

ci_usage() {
  cat >&2 <<'USAGE'
origin ci [<number>]

  Read one PR/MR and its current checks as JSON. No number uses this branch.
  Uses Origin's base remote and the forge CLI's GH_REPO/GITLAB_REPO context.

  Output: pr, checks, pipeline, checksState, stale.
  checksState: passed, failed, pending, blocked, or unknown.
  stale: the review or pipeline changed during the read, or the pipeline
         does not test the current source and target. Inspect again.

  Exit 0 means the snapshot was read, including pending or failed checks.
  A read or authentication error exits nonzero without a snapshot.
  A passed snapshot is not merge authorization; use origin merge's guards.
USAGE
}

ci_main() {
  local number='' selector pr after data kind
  while [ "$#" -gt 0 ]; do
    if parse_common_flag "$1"; then
      shift
      continue
    fi
    case "$1" in
      -h | --help) ci_usage; return 0 ;;
      *[!0-9]* | '') die "ci: expected a PR/MR number, got ${1}" ;;
      *)
        [ -z "$number" ] || die "ci takes one PR/MR number"
        number="$1"
        shift
        ;;
    esac
  done

  repo_require
  forge_require
  selector="${number:-$(repo_current_branch)}"
  [ -n "$selector" ] || die "HEAD is detached; pass a PR/MR number"
  pr="$(ci_read_review "$selector")"
  if [ -n "$number" ]; then
    [ "$(printf '%s' "$pr" | jq -r .number)" = "$number" ] ||
      die "the forge returned a different review number"
  fi
  number="$(printf '%s' "$pr" | jq -r .number)"
  kind="$(forge_kind)"
  case "$kind" in
    github) data="$(ci_github "$pr")" ;;
    gitlab) data="$(ci_gitlab "$pr")" ;;
    *) die "no forge to read CI from" ;;
  esac

  after="$(ci_read_review "$number")"
  printf '%s' "$data" | jq -c --argjson pr "$pr" --argjson after "$after" '
    . as $data |
    def identity: {number, url, state, headSha, headRef, baseRef, sourceProject,
      targetProject, checkCount, failingChecks, pendingChecks,
      pipeline: (.pipeline | {id, sha, project_id, status})};
    def checks_state:
      if length == 0 then "unknown"
      elif any(.bucket == "fail" or .bucket == "cancel") then "failed"
      elif any(.bucket == "blocked") then "blocked"
      elif any(.bucket == "pending") then "pending"
      elif all(.bucket == "pass" or .bucket == "skipping") then "passed"
      else "unknown" end;
    (($pr | identity) != ($after | identity) or ($data.stale // false)) as $stale |
    $data + {pr: ($after | {number, url, state, draft, headSha, headRef, baseRef,
      sourceProject, targetProject, mergeable, mergeStateStatus}), stale: $stale,
      checksState: (if $stale then "unknown" else ($data.checks | checks_state) end)}
  '
}

ci_read_review() {
  local pr
  pr="$(forge_pr_view "$1")" || die "could not read review ${1}"
  printf '%s' "$pr" | jq -e '
    (.number | type == "number") and (.url | type == "string") and
    (.state | type == "string") and
    (.headSha | strings | test("^[0-9a-fA-F]{40,64}$")) and
    (.headRef | type == "string") and (.baseRef | type == "string")
  ' >/dev/null || die "review identity is incomplete"
  printf '%s' "$pr" | jq -c '{number, url, state, draft, headSha, headRef,
    baseRef, sourceProject, targetProject, mergeable, mergeStateStatus,
    checkCount, failingChecks, pendingChecks, pipeline}'
}

ci_github() {
  local pr="$1" number checks status=0
  number="$(printf '%s' "$pr" | jq -r .number)"
  # gh exits without JSON when no checks exist. The review's rollup separates
  # that case from an API failure; absence remains unknown.
  if [ "$(printf '%s' "$pr" | jq -r .checkCount)" = 0 ]; then
    printf '{"checks":[],"pipeline":null}\n'
    return 0
  fi
  checks="$(gh pr checks "$number" --json name,state,bucket,link,workflow)" || status=$?
  case "$status" in
    0 | 1 | 8) ;;
    *) die "could not read GitHub checks for #${number}" ;;
  esac
  printf '%s' "$checks" | jq -e '
    type == "array" and all(.[]; (.name | type == "string") and
      (.bucket | type == "string"))
  ' >/dev/null || die "GitHub checks did not return a valid snapshot"
  printf '%s' "$checks" | jq -c '{checks: ., pipeline: null}'
}

ci_gitlab() {
  local pr="$1" id project number head pipeline jobs commit base branch association='head'
  id="$(printf '%s' "$pr" | jq -r '.pipeline.id // empty')"
  if [ -z "$id" ]; then
    printf '{"checks":[],"pipeline":null}\n'
    return 0
  fi
  project="$(printf '%s' "$pr" | jq -r '.pipeline.project_id // empty')"
  case "$id:$project" in
    *[!0-9:]* | :* | *:) die "the MR head pipeline has no valid project and pipeline IDs" ;;
  esac
  number="$(printf '%s' "$pr" | jq -r .number)"
  head="$(printf '%s' "$pr" | jq -r .headSha)"
  pipeline="$(glab api "projects/${project}/pipelines/${id}")" ||
    die "could not read GitLab pipeline ${project}/${id}"
  printf '%s' "$pipeline" | jq -e --argjson id "$id" --argjson project "$project" '
    .id == $id and .project_id == $project and
    (.sha | strings | test("^[0-9a-fA-F]{40,64}$")) and (.status | type == "string")
  ' >/dev/null || die "GitLab returned an incomplete or different pipeline"

  if [ "$(printf '%s' "$pipeline" | jq -r .sha)" != "$head" ]; then
    association=stale
    # A merged-result pipeline tests a generated commit. Bind both parents
    # to the MR source and live target rather than accepting any merge SHA.
    if [ "$(printf '%s' "$pipeline" | jq -r .ref)" = "refs/merge-requests/${number}/merge" ]; then
      commit="$(glab api "projects/${project}/repository/commits/$(printf '%s' "$pipeline" | jq -r .sha)")" ||
        die "could not read the merged-result commit"
      branch="$(printf '%s' "$pr" | jq -r '.baseRef | @uri')"
      base="$(glab api "projects/$(printf '%s' "$pr" | jq -r .targetProject)/repository/branches/${branch}")" ||
        die "could not read the pipeline target branch"
      if printf '%s' "$commit" | jq -e --arg head "$head" --argjson base "$base" --argjson pipeline "$pipeline" '
        .id == $pipeline.sha and (.parent_ids | type == "array") and
        (.parent_ids | index($head) != null) and
        ($base.commit.id | strings | test("^[0-9a-fA-F]{40,64}$")) and
        (.parent_ids | index($base.commit.id) != null)
      ' >/dev/null; then
        association=merge-result
      fi
    fi
  fi

  jobs="$(glab api "projects/${project}/pipelines/${id}/jobs?per_page=100" --paginate)" ||
    die "could not read jobs for GitLab pipeline ${project}/${id}"
  jobs="$(printf '%s' "$jobs" | jq -sce '
    if length > 0 and all(.[]; type == "array") then add else error("expected job pages") end
  ')" || die "GitLab jobs did not return valid pages"
  printf '%s' "$jobs" | jq -c --argjson pipeline "$pipeline" --arg association "$association" '
    . as $jobs |
    def bucket: .status as $status |
      if .status == "success" then "pass"
      elif .status == "skipped" then "skipping"
      elif .allow_failure == true and (.status == "failed" or .status == "manual") then "skipping"
      elif .status == "failed" then "fail"
      elif .status == "canceled" then "cancel"
      elif .status == "manual" then "blocked"
      elif (["created", "waiting_for_resource", "preparing", "pending", "running",
        "scheduled", "canceling", "waiting_for_callback"] | index($status)) != null then "pending"
      else "unknown" end;
    def check: {name: (.name // "pipeline"), id, state: .status, bucket: bucket, link: .web_url};
    {pipeline: ($pipeline | {id, project_id, sha, ref, status, web_url}) + {association: $association},
      stale: ($association == "stale"),
      checks: [($pipeline | check), ($jobs[] | check)]}
  '
}
