# shellcheck shell=bash
#
# Everything that has to be true before a command can work, checked in one
# place and reported at once.

# Each row carries its status in the first column so the caller can count
# failures. A `DOCTOR_FAILED` variable would not survive: the rows are produced
# on the left of a pipe, and the subshell takes the assignment with it.
doctor_row() {
  local status="$1" label="$2" detail="${3-}" mark
  case "$status" in
    ok) mark="${C_GREEN}ok${C_OFF}" ;;
    warn) mark="${C_YELLOW}--${C_OFF}" ;;
    *) mark="${C_RED}no${C_OFF}" ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$status" "$mark" "$label" "$detail"
}

doctor() {
  local arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      -h | --help)
        cat >&2 <<'USAGE'
origin doctor

  Check everything the other commands need: git, jq, the remote, the head
  branch, the forge CLI and its permissions.
USAGE
        return 0
        ;;
      *) die "doctor: unknown argument ${arg}" ;;
    esac
  done

  local rows failures
  rows="$(doctor_rows)"
  printf '%s\n' "$rows" | cut -f2- | tabulate
  blank

  failures="$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "no"' | grep -c . || true)"
  if [ "${failures:-0}" -gt 0 ]; then
    die "$(printf '%s check%s above needs fixing' "$failures" "$([ "$failures" = 1 ] || printf 's')")"
  fi
  good "ready"
}

doctor_rows() {
  doctor_tools
  git rev-parse --git-dir >/dev/null 2>&1 || {
    doctor_row no "repository" "not inside a git repository"
    return 0
  }
  doctor_repository
  doctor_forge
}

doctor_tools() {
  local version
  if command -v git >/dev/null 2>&1; then
    version="$(git --version | awk '{ print $3 }')"
    doctor_row ok "git" "$version"
  else
    doctor_row no "git" "not installed"
  fi
  if command -v jq >/dev/null 2>&1; then
    doctor_row ok "jq" "$(jq --version)"
  else
    doctor_row warn "jq" "not installed; the worktree commands work without it, merge does not"
  fi
}

doctor_repository() {
  local remote head root

  local status=0
  remote="$(repo_remote_compute 2>/dev/null)" || status=$?
  case "$status" in
    0)
      ORIGIN_REMOTE="$remote"
      doctor_row ok "remote" "${remote} → $(repo_remote_url)"
      ;;
    2) doctor_row no "remote" "several, and nothing says which; git config git-worktree-plugin.remote <name>" ;;
    *) doctor_row warn "remote" "none; the worktree commands still work" ;;
  esac

  if head="$(repo_head_branch 2>/dev/null)"; then
    doctor_row ok "head branch" "${head} ($(repo_head_ref))"
  else
    doctor_row no "head branch" "cannot tell; git config git-worktree-plugin.headBranch <name>"
  fi

  root="$(worktree_root)"
  if [ -d "$root" ] && [ -w "$root" ]; then
    doctor_row ok "worktree root" "$(worktree_pretty_path "$root")"
  elif [ -e "$root" ]; then
    doctor_row no "worktree root" "${root} is not writable"
  elif [ -w "$(dirname "$root")" ]; then
    doctor_row ok "worktree root" "$(worktree_pretty_path "$root") (will be created)"
  else
    doctor_row no "worktree root" "$(dirname "$root") is not writable"
  fi
}

doctor_forge() {
  local kind host cli policy permission

  kind="$(forge_kind)"
  host="$(forge_host)"
  if [ "$kind" = none ]; then
    doctor_row warn "forge" "${host:-no remote} is not a GitHub or GitLab this machine is signed in to; merge is unavailable"
    return 0
  fi
  cli="$(forge_cli)"
  doctor_row ok "forge" "${kind} at ${host}"

  if ! command -v "$cli" >/dev/null 2>&1; then
    doctor_row no "${cli}" "not installed"
    return 0
  fi
  if ! "$cli" auth status --hostname "$host" >/dev/null 2>&1; then
    doctor_row no "${cli} auth" "run: ${cli} auth login --hostname ${host}"
    return 0
  fi
  doctor_row ok "${cli} auth" "signed in to ${host}"

  case "$kind" in
    github)
      permission="$(gh repo view --json viewerPermission --jq '.viewerPermission // ""' 2>/dev/null || printf '')"
      ;;
    gitlab)
      # shellcheck disable=SC2016  # $l is a jq variable
      permission="$(glab api projects/:fullpath --jq '
        (.permissions.project_access.access_level // .permissions.group_access.access_level // 0) as $l
        | if $l >= 40 then "MAINTAIN" elif $l >= 30 then "WRITE" elif $l > 0 then "READ" else "" end' 2>/dev/null || printf '')"
      ;;
  esac
  case "$permission" in
    ADMIN | MAINTAIN | WRITE) doctor_row ok "permission" "$permission" ;;
    '') doctor_row warn "permission" "could not read it" ;;
    *) doctor_row no "permission" "${permission}; merging needs write" ;;
  esac

  policy="$(forge_merge_policy)"
  doctor_row ok "merge methods" "default ${policy%% *}, allowed ${policy##* }"
}
