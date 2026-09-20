# shellcheck shell=bash
#
# Deleting the branches whose change the head branch already has.
#
# Two kinds of finished branch, and they are not equally safe to delete. One
# has a merged pull request behind it: the forge holds the change and offers
# the branch back from the pull request's own page, so deleting it costs a
# click to undo. The other was proved finished by its content alone, which
# `merged.sh` does by asking whether the branch's tree is already upstream,
# and behind that one there is nothing but this clone. It is printed with the
# command that deletes it, and left where it is.
#
# `git branch --merged` is not the question. Most branches now end in a squash,
# which leaves their commits reachable from nothing, so that reading calls
# every finished branch unfinished and the list stops being read.

prune_usage() {
  cat >&2 <<'USAGE'
origin prune [flags]

  Delete the branches whose change the head branch already has.

  A branch with a merged pull request goes here and on the remote. The forge
  keeps the change and restores the branch from the pull request's own page,
  so the deletion has somewhere to come back from.

  A branch proved finished by its content, with no merged pull request behind
  it, is printed with the command that deletes it. Nothing deletes that one
  for you.

  Left alone: the branch you are on, the head branch, a branch checked out in
  another worktree, one whose pull request is still open, and one holding
  commits no remote has.

  --dry-run    Say what would happen
  --yes        Do not ask
USAGE
}

# Branches git is standing on, in this worktree and every other. Deleting one
# is refused by git itself, and naming the worktree that holds it is the
# difference between a refusal and an errand.
prune_checked_out() {
  git worktree list --porcelain 2>/dev/null |
    awk '$1 == "branch" { sub(/^refs\/heads\//, "", $2); print $2 }'
}

# Is the forge reachable? Asked once: the answer runs `gh auth status`, and a
# repository with twenty stale branches would run it twenty times.
PRUNE_FORGE=''
prune_forge_ok() {
  if [ -z "$PRUNE_FORGE" ]; then
    if forge_available; then PRUNE_FORGE=1; else PRUNE_FORGE=0; fi
  fi
  [ "$PRUNE_FORGE" = 1 ]
}

# One row per branch: <verdict> <branch> <sha> <why>, ORIGIN_FS-separated.
PRUNE_ROWS=''
PRUNE_UNFINISHED=0

prune_row() {
  PRUNE_ROWS="${PRUNE_ROWS}${1}${ORIGIN_FS}${2}${ORIGIN_FS}${3}${ORIGIN_FS}${4}"$'\n'
}

prune_rows_of() {
  printf '%s' "$PRUNE_ROWS" | awk -F"$ORIGIN_FS" -v want="$1" '$1 == want'
}

# What the forge says about this branch, or nothing.
#
# The bulk answer is loaded by the caller, in its own shell, because a command
# substitution here would remember it in a subshell that is thrown away.
prune_pr_state() {
  local branch="$1" answer
  prune_forge_ok || return 0
  answer="$(forge_pr_state_for "$branch")"
  printf '%s' "$answer"
}

prune_classify() {
  local head="$1" head_ref="$2" current="$3"
  local checked_out branch sha reason unpushed answer state number word

  checked_out="$(prune_checked_out)"

  while IFS= read -r branch; do
    [ -n "$branch" ] || continue
    [ "$branch" = "$head" ] && continue

    sha="$(git rev-parse --short "refs/heads/${branch}" 2>/dev/null || printf '')"

    # Asked first, so the report is the finished branches and nothing else. A
    # branch with work still on it is a count at the end, not a row to read.
    reason="$(merged_reason "$branch" "$head_ref" 2>/dev/null || printf '')"
    if [ -z "$reason" ]; then
      PRUNE_UNFINISHED=$((PRUNE_UNFINISHED + 1))
      continue
    fi

    if [ "$branch" = "$current" ]; then
      prune_row keep "$branch" "$sha" 'the branch you are on'
      continue
    fi

    if printf '%s\n' "$checked_out" | grep -qxF -- "$branch"; then
      prune_row keep "$branch" "$sha" 'checked out in another worktree'
      continue
    fi

    # A merged pull request says the pushed part of the branch is upstream. It
    # says nothing about commits that never left this clone.
    unpushed="$(merged_unpushed_count "$branch")"
    if [ "${unpushed:-0}" -gt 0 ]; then
      word='commits'
      [ "$unpushed" = 1 ] && word='commit'
      prune_row keep "$branch" "$sha" "${unpushed} ${word} no remote has"
      continue
    fi

    answer="$(prune_pr_state "$branch")"
    state="${answer%%	*}"
    number="${answer#*	}"
    [ "$answer" = "$state" ] && number=''

    case "$state" in
      MERGED) prune_row delete "$branch" "$sha" "${reason}, $(forge_noun) #${number}" ;;
      OPEN) prune_row keep "$branch" "$sha" "$(forge_noun) #${number} is still open" ;;
      *) prune_row suggest "$branch" "$sha" "${reason}, no merged $(forge_noun)" ;;
    esac
  done < <(git for-each-ref --format='%(refname:short)' refs/heads/)
}

prune_report() {
  local rows
  rows="$(printf '%s' "$PRUNE_ROWS" | awk -F"$ORIGIN_FS" '{ print $1 "\t" $2 "\t" $3 "\t" $4 }')"
  [ -n "$rows" ] || return 0
  blank
  note 'Finished branches'
  printf '%s\n' "$rows" | tabulate
}

# Deleting one branch, here and on the remote it was pushed to.
#
# The remote side is skipped where the remote-tracking ref has already gone,
# which is what a forge that deletes the head branch on merge leaves behind.
prune_delete_one() {
  local branch="$1" remote="$2" previous="$ORIGIN_ALLOW_FORCE_DELETE"

  # The two things the guard asks for: a proof the change is upstream, which
  # is the verdict that put this branch in the delete list, and a caller that
  # says so deliberately.
  ORIGIN_ALLOW_FORCE_DELETE=1
  git_run branch -D "$branch"
  ORIGIN_ALLOW_FORCE_DELETE="$previous"

  if [ -n "$remote" ] && git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"; then
    git_run push "$remote" --delete "refs/heads/${branch}"
  fi
}

prune_delete_all() {
  local remote="$1" branch sha why commands=() losses=()

  while IFS="$ORIGIN_FS" read -r _ branch sha why; do
    [ -n "$branch" ] || continue
    commands+=("git branch -D ${branch}")
    if git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"; then
      commands+=("git push ${remote} --delete refs/heads/${branch}")
    fi
    losses+=("${branch} at ${sha} — ${why}, restore it from there or with: git branch ${branch} ${sha}")
  done < <(prune_rows_of delete)

  [ "${#commands[@]}" -gt 0 ] || return 0

  losing 'What goes:' "${losses[@]}"
  confirm 'Delete them?' "${commands[@]}"

  while IFS="$ORIGIN_FS" read -r _ branch _ _; do
    [ -n "$branch" ] || continue
    prune_delete_one "$branch" "$remote"
  done < <(prune_rows_of delete)
}

prune_suggest_all() {
  local remote="$1" branch sha why lines=()

  while IFS="$ORIGIN_FS" read -r _ branch sha why; do
    [ -n "$branch" ] || continue
    lines+=("git branch -D ${branch}    # ${why}, at ${sha}")
    if git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"; then
      lines+=("git push ${remote} --delete refs/heads/${branch}")
    fi
  done < <(prune_rows_of suggest)

  [ "${#lines[@]}" -gt 0 ] || return 0

  blank
  note 'Nothing on the forge holds these, so they are yours to delete:'
  printf '  %s\n' "${lines[@]}" >&2
}

prune_main() {
  local arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      -h | --help)
        prune_usage
        return 0
        ;;
      *) die "prune: takes no arguments; it reads every branch in this clone" ;;
    esac
  done

  repo_require

  local head head_ref current remote
  repo_fetch
  head="$(repo_head_branch)"
  head_ref="$(repo_head_ref_for "$head")"
  git rev-parse --verify --quiet "${head_ref}^{commit}" >/dev/null ||
    die "there is no $(ref_name "$head_ref") to judge a branch against"
  current="$(repo_current_branch)"
  remote="$(repo_remote 2>/dev/null || printf '')"

  # Loaded here, in this shell, so that every lookup in the loop is free.
  prune_forge_ok && forge_pr_bulk_load

  prune_classify "$head" "$head_ref" "$current"
  prune_report

  prune_delete_all "$remote"
  prune_suggest_all "$remote"

  blank
  if [ "$PRUNE_UNFINISHED" -gt 0 ]; then
    local word='branches hold'
    [ "$PRUNE_UNFINISHED" = 1 ] && word='branch holds'
    note "${PRUNE_UNFINISHED} ${word} work $(ref_name "$head_ref") has not got"
  else
    good "every branch here is in $(ref_name "$head_ref")"
  fi
}
