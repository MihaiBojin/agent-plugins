# shellcheck shell=bash
#
# GitHub and GitLab behind one surface. Nothing above this file knows which is
# in play.
#
# Commit messages and a diffstat are read from local git rather than an API:
# they are already in the clone, exactly, and the same code then serves both
# forges. The API is the fallback for a pull request whose head is a fork this
# clone has never fetched.

FORGE_PR_JSON=''
FORGE_PR_BULK=''
FORGE_PR_BULK_LOADED=0
FORGE_KIND=''

forge_host_of() {
  local url="$1" host=''
  case "$url" in
    '') ;;
    *://*)
      host="${url#*://}"
      host="${host#*@}"
      host="${host%%/*}"
      host="${host%%:*}"
      ;;
    *@*:*)
      host="${url#*@}"
      host="${host%%:*}"
      ;;
  esac
  printf '%s\n' "$host"
}

# The host of the remote this repository belongs to.
#
# A `url.<base>.insteadOf` rewrite can point the transport somewhere that says
# nothing about the forge, so when the rewritten URL is not recognisable the
# one written in config is tried too.
forge_host() {
  local host raw
  host="$(forge_host_of "$(repo_remote_url)")"
  case "$host" in
    github.com | *.github.com | gitlab.com | gitlab.* | *.gitlab.com)
      printf '%s\n' "$host"
      return 0
      ;;
  esac
  raw="$(forge_host_of "$(repo_remote_url_raw)")"
  if [ -n "$raw" ]; then
    printf '%s\n' "$raw"
  else
    printf '%s\n' "$host"
  fi
}

# github | gitlab | none.
#
# The hostname answers for the two public instances. For anything else the
# CLIs are asked, because a GitHub Enterprise server at git.example.com is
# something `gh` already knows about and the user should not have to say twice.
forge_kind() {
  [ -z "$FORGE_KIND" ] || {
    printf '%s\n' "$FORGE_KIND"
    return 0
  }

  local host
  host="$(forge_host)"
  case "$host" in
    github.com | *.github.com) FORGE_KIND=github ;;
    gitlab.com | gitlab.* | *.gitlab.com) FORGE_KIND=gitlab ;;
    '') FORGE_KIND=none ;;
    *)
      FORGE_KIND=none
      if command -v gh >/dev/null 2>&1 && gh auth status --hostname "$host" >/dev/null 2>&1; then
        FORGE_KIND=github
      elif command -v glab >/dev/null 2>&1 && glab auth status --hostname "$host" >/dev/null 2>&1; then
        FORGE_KIND=gitlab
      fi
      ;;
  esac
  printf '%s\n' "$FORGE_KIND"
}

forge_cli() {
  case "$(forge_kind)" in
    github) printf 'gh\n' ;;
    gitlab) printf 'glab\n' ;;
    *) printf '\n' ;;
  esac
}

forge_noun() {
  case "$(forge_kind)" in
    gitlab) printf 'merge request\n' ;;
    *) printf 'pull request\n' ;;
  esac
}

# Whether the forge can be asked anything, without dying if it cannot.
forge_available() {
  case "$(forge_kind)" in
    github)
      command -v gh >/dev/null 2>&1 || return 1
      command -v jq >/dev/null 2>&1 || return 1
      gh auth status >/dev/null 2>&1
      ;;
    gitlab)
      command -v glab >/dev/null 2>&1 || return 1
      command -v jq >/dev/null 2>&1 || return 1
      glab auth status >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

forge_require() {
  local kind host
  kind="$(forge_kind)"
  host="$(forge_host)"
  case "$kind" in
    github)
      require_cmd gh "see https://cli.github.com"
      gh auth status --hostname "$host" >/dev/null 2>&1 ||
        die "gh is not authenticated for ${host}; run: gh auth login --hostname ${host}"
      ;;
    gitlab)
      require_cmd glab "see https://gitlab.com/gitlab-org/cli"
      glab auth status --hostname "$host" >/dev/null 2>&1 ||
        die "glab is not authenticated for ${host}; run: glab auth login --hostname ${host}"
      ;;
    *)
      die "neither gh nor glab is authenticated for ${host:-this remote}; run: gh auth login --hostname ${host:-<host>}"
      ;;
  esac
  require_cmd jq "it is what reads what ${kind} returns"
}

# The merge method the repository itself prefers, and the ones it allows.
# Prints "<default> <allowed,...>".
forge_merge_policy() {
  case "$(forge_kind)" in
    github)
      gh repo view --json viewerDefaultMergeMethod,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed --jq '
        [ (.viewerDefaultMergeMethod // "SQUASH" | ascii_downcase),
          ([ (if .squashMergeAllowed then "squash" else empty end),
             (if .mergeCommitAllowed then "merge" else empty end),
             (if .rebaseMergeAllowed then "rebase" else empty end) ] | join(","))
        ] | join(" ")' 2>/dev/null || printf 'squash squash,merge,rebase\n'
      ;;
    gitlab)
      glab api projects/:fullpath --jq '
        (if .squash_option == "always" then "squash"
         elif .merge_method == "ff" then "rebase"
         else "merge" end) + " squash,merge,rebase"' 2>/dev/null || printf 'merge squash,merge,rebase\n'
      ;;
    *) printf 'squash squash,merge,rebase\n' ;;
  esac
}

# One pull request, in this plugin's shape rather than either forge's.
#
#   { number, title, body, state, url, author, draft, baseRef, headRef,
#     crossRepository, mergeable, mergeStateStatus,
#     failingChecks: [name...], pendingChecks: [name...] }
#
# The selector is whatever the CLI resolves: a number, or a branch. Both forges
# take either.
#
# `crossRepository` is load-bearing rather than informational. `headRef` is the
# bare branch name, so a pull request from someone else's fork of `main` says
# `main` - the same string this repository's own default branch answers to, and
# nothing else tells a local ref of that name from the fork's branch.
forge_pr_view() {
  local selector="$1" raw
  forge_require
  case "$(forge_kind)" in
    github)
      raw="$(gh pr view "$selector" \
        --json number,title,body,state,url,author,isDraft,isCrossRepository,mergeable,mergeStateStatus,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,statusCheckRollup \
        2>/dev/null || printf '')"
      [ -n "$raw" ] || return 1
      printf '%s' "$raw" | jq -c '
        # A check run reports .status and .conclusion; a commit status reports
        # only .state. Both arrive in the same list, so both are read. The
        # fields are bound before the lists, because inside index() the input
        # is the list rather than the check.
        def failed:
          ((.conclusion // "") | ascii_upcase) as $conclusion
          | ((.state // "") | ascii_upcase) as $state
          | (["FAILURE","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"]
               | index($conclusion)) != null
            or (["FAILURE","ERROR"] | index($state)) != null;
        def unfinished:
          ((.status // "") | ascii_upcase) as $status
          | ((.state // "") | ascii_upcase) as $state
          | (["QUEUED","IN_PROGRESS","WAITING","PENDING","REQUESTED"]
               | index($status)) != null
            or (["PENDING","EXPECTED"] | index($state)) != null;
        def check_name: (.name // .context // "check");
        {
          number: .number,
          title: .title,
          body: (.body // ""),
          state: .state,
          url: .url,
          author: (.author.login // ""),
          draft: (.isDraft // false),
          baseRef: .baseRefName,
          headRef: .headRefName,
          headSha: .headRefOid,
          sourceProject: (if .headRepository.name then
            .headRepositoryOwner.login + "/" + .headRepository.name else null end),
          targetProject: (if .url then .url | split("/") | .[0:5] | join("/") else null end),
          checkCount: ((.statusCheckRollup // []) | length),
          crossRepository: (.isCrossRepository // false),
          mergeable: (.mergeable // "UNKNOWN"),
          mergeStateStatus: (.mergeStateStatus // "UNKNOWN"),
          failingChecks: [ (.statusCheckRollup // [])[] | select(failed) | check_name ],
          pendingChecks: [
            (.statusCheckRollup // [])[] | select(failed | not) | select(unfinished) | check_name
          ]
        }'
      ;;
    gitlab)
      raw="$(glab mr view "$selector" --output json 2>/dev/null || printf '')"
      [ -n "$raw" ] || return 1
      printf '%s' "$raw" | jq -c '
        def state: (.state // "") | ascii_downcase
          | if . == "opened" then "OPEN"
            elif . == "merged" then "MERGED"
            elif . == "closed" then "CLOSED"
            elif . == "locked" then "OPEN"
            else ascii_upcase end;
        def status: (.detailed_merge_status // .merge_status // "") | ascii_downcase;
        {
          number: .iid,
          title: .title,
          body: (.description // ""),
          state: state,
          url: (.web_url // ""),
          author: (.author.username // ""),
          draft: (.draft // .work_in_progress // false),
          baseRef: .target_branch,
          headRef: .source_branch,
          headSha: (.sha // .diff_refs.head_sha),
          sourceProject: .source_project_id,
          targetProject: .target_project_id,
          pipeline: .head_pipeline,
          crossRepository: (
            if (.source_project_id != null and .target_project_id != null)
            then .source_project_id != .target_project_id else false end
          ),
          mergeable: (
            if (.has_conflicts // false) then "CONFLICTING"
            elif status == "mergeable" or status == "can_be_merged" then "MERGEABLE"
            else "UNKNOWN" end
          ),
          mergeStateStatus: (
            if status == "mergeable" or status == "can_be_merged" then "CLEAN"
            elif status == "ci_still_running" then "PENDING"
            elif status == "" then "UNKNOWN"
            elif status == "checking" or status == "unchecked" then "UNKNOWN"
            else "BLOCKED" end
          ),
          failingChecks: (
            if ((.head_pipeline.status // "") | ascii_downcase) == "failed"
            then ["pipeline"] else [] end
          ),
          pendingChecks: (
            ((.head_pipeline.status // "") | ascii_downcase) as $pipeline
            | if (["created","waiting_for_resource","preparing","pending","running","scheduled"]
                  | index($pipeline)) != null
              then ["pipeline"] else [] end
          )
        }'
      ;;
  esac
}

# Loads a pull request once, and remembers it: the merge command asks the same
# four questions of it.
forge_pr_load() {
  local branch="$1"
  FORGE_PR_JSON="$(forge_pr_view "$branch" || printf '')"
  [ -n "$FORGE_PR_JSON" ]
}

# The pull request that was named, and no other.
#
# Loading it by number and then checking the number back is not tautology: a
# branch reused after its first pull request merged has two, so resolving a
# number to a branch and looking the branch up again can land on the other one
# - and the merge that follows would be of a pull request nobody named.
forge_pr_load_number() {
  local number="$1"
  forge_pr_load "$number" || return 1
  [ "$(forge_pr_field .number)" = "$number" ] || return 1
}

forge_pr_field() {
  [ -n "$FORGE_PR_JSON" ] || return 1
  printf '%s' "$FORGE_PR_JSON" | jq -r "${1} // \"\""
}

# The two refs a pull request is a range between, when this clone has both.
#
# Against the remote this repository belongs to, not `origin`: on the fork
# layout the plugin itself recommends - `git config checkout.defaultRemote
# upstream` - the pull request's refs live under `upstream/`, and `origin/` is
# the fork, whose refs are a different branch of the same name or nothing.
#
# A pull request from a fork has no local range at all, whatever refs happen to
# match its branch names, so it goes to the API instead.
#
# Full refs. The two names come from the forge, and nothing stops a repository
# holding a tag called `origin/main` that git would resolve first.
forge_pr_range() {
  local base head remote
  [ "$(forge_pr_field .crossRepository)" = "true" ] && return 1
  base="$(forge_pr_field .baseRef)"
  head="$(forge_pr_field .headRef)"
  [ -n "$base" ] && [ -n "$head" ] || return 1
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$remote" ] || return 1
  git show-ref --verify --quiet "refs/remotes/${remote}/${base}" || return 1
  git show-ref --verify --quiet "refs/remotes/${remote}/${head}" || return 1
  printf 'refs/remotes/%s/%s refs/remotes/%s/%s\n' "$remote" "$base" "$remote" "$head"
}

# Commits, as [{sha, author, subject, body}], oldest first.
forge_pr_commits() {
  local number="${1:-}" range base head record rest sha author subject body first=1

  if range="$(forge_pr_range)"; then
    base="${range%% *}"
    head="${range##* }"
    printf '['
    while IFS= read -r -d $'\036' record; do
      record="${record#$'\n'}"
      [ -n "$record" ] || continue
      sha="${record%%$'\037'*}"
      rest="${record#*$'\037'}"
      author="${rest%%$'\037'*}"
      rest="${rest#*$'\037'}"
      subject="${rest%%$'\037'*}"
      body="${rest#*$'\037'}"
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{%s,%s,%s,%s}' \
        "$(json_field sha "$sha")" \
        "$(json_field author "$author")" \
        "$(json_field subject "$subject")" \
        "$(json_field body "$body")"
    done < <(git log --reverse --format='%H%x1f%an <%ae>%x1f%s%x1f%b%x1e' "${base}..${head}")
    printf ']\n'
    return 0
  fi

  forge_pr_api_commits "$number"
}

# When the range is not in this clone - a fork, or a branch nobody fetched.
forge_pr_api_commits() {
  local number="$1"
  case "$(forge_kind)" in
    github)
      gh pr view "$number" --json commits --jq '
        [ .commits[] | {
            sha: .oid,
            author: ((.authors // [])[0] | ((.name // "") + " <" + (.email // "") + ">")),
            subject: .messageHeadline,
            body: (.messageBody // "")
          } ]' 2>/dev/null || printf '[]\n'
      ;;
    gitlab)
      glab api "projects/:fullpath/merge_requests/${number}/commits" --jq '
        [ .[] | {
            sha: .id,
            author: ((.author_name // "") + " <" + (.author_email // "") + ">"),
            subject: .title,
            body: ((.message // "") | sub("^[^\n]*\n*"; ""))
          } ] | reverse' 2>/dev/null || printf '[]\n'
      ;;
    *) printf '[]\n' ;;
  esac
}

# { files, insertions, deletions, changed: [path...] }
forge_pr_diffstat() {
  local number="${1:-}" range base head added=0 removed=0 files=0 add del path first=1 paths=''

  if range="$(forge_pr_range)"; then
    base="${range%% *}"
    head="${range##* }"
    while IFS=$'\t' read -r add del path; do
      [ -n "$path" ] || continue
      files=$((files + 1))
      case "$add" in '-') ;; *) added=$((added + add)) ;; esac
      case "$del" in '-') ;; *) removed=$((removed + del)) ;; esac
      [ "$first" = 1 ] || paths="${paths},"
      first=0
      paths="${paths}$(json_string "$path")"
    done < <(git diff --numstat "${base}...${head}")
    printf '{%s,%s,%s,%s}\n' \
      "$(json_raw_field files "$files")" \
      "$(json_raw_field insertions "$added")" \
      "$(json_raw_field deletions "$removed")" \
      "$(json_raw_field changed "[${paths}]")"
    return 0
  fi

  case "$(forge_kind)" in
    github)
      gh pr view "$number" --json files --jq '{
        files: (.files | length),
        insertions: ([.files[].additions] | add // 0),
        deletions: ([.files[].deletions] | add // 0),
        changed: [.files[].path]
      }' 2>/dev/null || printf '{"files":0,"insertions":0,"deletions":0,"changed":[]}\n'
      ;;
    gitlab)
      glab api "projects/:fullpath/merge_requests/${number}/changes" --jq '{
        files: ((.changes // []) | length),
        insertions: 0,
        deletions: 0,
        changed: [(.changes // [])[].new_path]
      }' 2>/dev/null || printf '{"files":0,"insertions":0,"deletions":0,"changed":[]}\n'
      ;;
    *) printf '{"files":0,"insertions":0,"deletions":0,"changed":[]}\n' ;;
  esac
}

# Is this pull request in a stack?
#
# GitHub refuses `gh pr merge` for anything in one: it merges over GraphQL, and
# `mergePullRequest` answers that the pull request "must be merged using the
# asynchronous merge REST API". The synchronous REST endpoint refuses it too.
# A pull request is in a stack when anything is stacked on it, so the bottom
# one - based on the head branch, mergeable by hand - is refused as well.
#
# The REST object's `stack` field is the whole answer: an object inside a
# stack, and no key at all outside one. Read rather than matched on the
# refusal, which is English, worded differently by the two endpoints, and
# arrives only once the body has been written and approved.
forge_pr_stacked() {
  local number="$1"
  [ "$(forge_kind)" = github ] || return 1
  [ "$(gh api "repos/{owner}/{repo}/pulls/${number}" --jq '.stack != null' 2>/dev/null)" = "true" ]
}

# What the asynchronous endpoint takes. The same fields as the synchronous one,
# spelled differently: `merge_method` is the bare word, without the dashes
# `gh pr merge` wants. `commit_title` is passed through as written, so the
# `(#12)` already on it stays on the squashed commit.
forge_merge_async_payload() {
  local method="$1" title="$2" body_file="$3" body=''
  if [ -n "$body_file" ]; then
    body="$(cat "$body_file")"
  fi
  jq -n --arg method "${method#--}" --arg title "$title" --arg body "$body" '
    { merge_method: $method }
    + (if $title == "" then {} else { commit_title: $title } end)
    + (if $body == "" then {} else { commit_message: $body } end)'
}

# The merge a stack gets: PUT merge-async, then wait for GitHub to say it
# landed.
#
# The endpoint returns as soon as the merge is queued, so `merged` is not what
# it usually answers first. Everything after the PUT is waiting for one.
forge_merge_async() {
  local number="$1" method="$2" title="$3" body_file="$4"
  local path="repos/{owner}/{repo}/pulls/${number}/merge-async"
  local payload result status uuid

  note "#${number} is in a stack; GitHub merges those in the background"
  payload="$(forge_merge_async_payload "$method" "$title" "$body_file")"

  if [ "$ORIGIN_DRY_RUN" = 1 ]; then
    origin_run gh api --method PUT "$path" --input -
    return 0
  fi

  debug "$(quote_args gh api --method PUT "$path" --input -)"
  result="$(printf '%s' "$payload" | gh api --method PUT "$path" --input -)" || return 1

  status="$(printf '%s' "$result" | jq -r '.status // ""' 2>/dev/null || printf '')"
  case "$status" in
    merged) return 0 ;;
    failed)
      die "GitHub refused the merge: $(printf '%s' "$result" | jq -r '.details.message // "it gave no reason"')"
      ;;
    # `enqueued` is a merge queue holding it, and a queue can take longer than
    # anything waited for here. Nothing in this plugin has been run against
    # one, so it is waited on like `pending` and reported the same way.
    pending | enqueued) ;;
    *) die "GitHub answered '${status:-nothing}' to the merge of #${number}" ;;
  esac

  uuid="$(printf '%s' "$result" | jq -r '.details.uuid // ""')"
  [ -n "$uuid" ] || die "GitHub queued the merge of #${number} without an id to follow it by"
  forge_merge_async_wait "$number" "$uuid"
}

# Waits for a queued merge to land.
#
# The merge request's own status is what says it did: `merged` is done, and
# `failed` carries a reason, which is a refusal to report rather than something
# to try again. The pull request's state is read beside it because GitHub is
# free to forget the request - a merge that landed and then lost its record
# must not come back from here as a failure.
#
# Sixty checks, five seconds apart. Both numbers are a guess. The two variables
# exist so a test does not sleep.
forge_merge_async_wait() {
  local number="$1" uuid="$2"
  local tries="${ORIGIN_MERGE_ASYNC_TRIES:-60}" wait="${ORIGIN_MERGE_ASYNC_WAIT:-5}" try=1
  local result status

  while :; do
    result="$(gh api "repos/{owner}/{repo}/pulls/${number}/merge-async/${uuid}" 2>/dev/null || printf '')"
    status="$(printf '%s' "$result" | jq -r '.status // ""' 2>/dev/null || printf '')"
    case "$status" in
      merged) return 0 ;;
      failed)
        die "GitHub could not merge #${number}: $(printf '%s' "$result" | jq -r '.details.message // "it gave no reason"')"
        ;;
    esac
    if [ "$(gh pr view "$number" --json state --jq '.state' 2>/dev/null || printf '')" = "MERGED" ]; then
      return 0
    fi
    [ "$try" -lt "$tries" ] || break
    if [ "$wait" -gt 0 ]; then
      sleep "$wait"
    fi
    try=$((try + 1))
  done

  die "#${number} was still ${status:-unreported} after ${try} checks; a merge queue can hold one longer than that, so read the pull request before merging it again"
}

# Merges. The one call in this plugin that cannot be taken back.
#
#   forge_pr_merge <number> --squash|--merge|--rebase --title T --body-file F
forge_pr_merge() {
  local number="$1" method='--squash' title='' body_file=''
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --squash | --merge | --rebase) method="$1" ;;
      --title)
        require_value --title "${@:2}"
        title="$2"
        shift
        ;;
      --body-file)
        require_value --body-file "${@:2}"
        body_file="$2"
        shift
        ;;
      *) die "forge_pr_merge: unknown argument ${1}" ;;
    esac
    shift
  done

  case "$(forge_kind)" in
    github)
      if forge_pr_stacked "$number"; then
        forge_merge_async "$number" "$method" "$title" "$body_file"
        return
      fi
      set -- gh pr merge "$number" "$method"
      [ -n "$title" ] && set -- "$@" --subject "$title"
      [ -n "$body_file" ] && set -- "$@" --body-file "$body_file"
      origin_run "$@"
      ;;
    gitlab)
      # glab has no subject and body; a squash message is one blob, and
      # auto-merge would otherwise wait for a pipeline nobody asked it to.
      local message=''
      if [ -n "$title" ]; then
        message="$title"
        [ -n "$body_file" ] && message="${message}"$'\n\n'"$(cat "$body_file")"
      fi
      set -- glab mr merge "$number" --yes --auto-merge=false
      case "$method" in
        --squash)
          set -- "$@" --squash
          [ -n "$message" ] && set -- "$@" --squash-message "$message"
          ;;
        --rebase) set -- "$@" --rebase ;;
        --merge) [ -n "$message" ] && set -- "$@" --message "$message" ;;
      esac
      origin_run "$@"
      ;;
    *) die "no forge to merge with" ;;
  esac
}

# Marks a draft ready for review.
#
# This changes the pull request rather than reading it: undrafting can start
# required checks and request reviews the draft never had, so whatever was
# decided from the previous reading is stale afterwards.
forge_pr_mark_ready() {
  local number="$1"
  case "$(forge_kind)" in
    github) origin_run gh pr ready "$number" ;;
    gitlab) origin_run glab mr update "$number" --ready ;;
    *) die "no forge to mark it ready on" ;;
  esac
}

# Every branch's pull-request state, in one call.
#
# `wt clean` in a repository with thirty stale branches must not make thirty
# requests. The answer is read once and indexed here, as TSV:
#
#   <branch>\t<state>\t<number>
#
# The load is a function of its own because a pipeline and a command
# substitution both run in a subshell, where the assignment that remembers the
# answer would be thrown away the moment it was made - so the caller loads it
# in its own shell, once, and every lookup after that is free.
forge_pr_bulk_load() {
  [ "$FORGE_PR_BULK_LOADED" = 1 ] && return 0
  FORGE_PR_BULK_LOADED=1
  case "$(forge_kind)" in
    github)
      FORGE_PR_BULK="$(gh pr list --state all --limit 200 \
        --json number,headRefName,state \
        --jq '.[] | [.headRefName, (.state | ascii_upcase), (.number | tostring)] | @tsv' \
        2>/dev/null || printf '')"
      ;;
    gitlab)
      FORGE_PR_BULK="$(glab mr list --all --per-page 100 --output json \
        --jq '.[] | [.source_branch, (.state | ascii_upcase | if . == "OPENED" then "OPEN" else . end), (.iid | tostring)] | @tsv' \
        2>/dev/null || printf '')"
      ;;
    *) FORGE_PR_BULK='' ;;
  esac
  return 0
}

forge_pr_state_bulk() {
  forge_pr_bulk_load
  printf '%s\n' "$FORGE_PR_BULK"
}

# "<state>\t<number>" for one branch, or empty. Newest entry wins: a branch
# reused after its first pull request merged is a branch with two.
forge_pr_state_for() {
  local branch="$1"
  forge_pr_bulk_load
  printf '%s\n' "$FORGE_PR_BULK" |
    awk -F'\t' -v branch="$branch" '$1 == branch { print $2 "\t" $3; exit }'
}
