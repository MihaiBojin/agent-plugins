# shellcheck shell=bash
#
# Renewing a branch: putting it back on top of the head branch, or starting the
# next one when it cannot go back on top.
#
# Three shapes, decided by what the branch is rather than by what was typed.
#
# On the head branch there is one safe move, a fast-forward, and it refuses if
# that would drop a local commit.
#
# On an unfinished branch the move is a rebase, which is what "catch up" means
# when the commits are still yours to rewrite.
#
# On a branch whose change is already in the head branch there is no move at
# all. A squash merge rewrites the branch into one commit, so git can no longer
# match the branch's patches against it; a rebase then replays work the head
# branch already has and stops on it, commit after commit. The change is
# finished, so the next one starts on a new branch and this one is left where
# it is.

sync_usage() {
  cat >&2 <<'USAGE'
origin sync [flags]

  Fetch, put this branch back on top of the head branch, and push it.

  A branch whose change is already in the head branch cannot be rebased onto
  it. That one is finished: `origin new <name>` starts the next change, and
  this branch is left where it is.

  --branch <name>   The branch to carry or cherry-pick onto
  --squash          Do not rebase; carry the whole change onto a new branch
  --commit          Commit what is in the tree first, asking for the message
  --message <text>  The same, with the message given rather than asked for
  --probe           With --squash: say whether it would apply cleanly, and stop
  --autostash       Stash before and re-apply after, via git's own
  --push            Push afterwards: plain for a new branch, leased for a known one
  --dry-run         Say what would happen
  --yes             Do not ask
USAGE
}

sync_main() {
  local autostash=0 push=0 squash=0 probe=0 name='' message='' commit=0 arg
  while [ "$#" -gt 0 ]; do
    arg="$1"
    if parse_common_flag "$arg"; then
      shift
      continue
    fi
    case "$arg" in
      --branch)
        require_value --branch "${@:2}"
        name="$2"
        shift 2
        ;;
      --squash)
        squash=1
        shift
        ;;
      --probe)
        probe=1
        shift
        ;;
      --autostash)
        autostash=1
        shift
        ;;
      --commit)
        commit=1
        shift
        ;;
      --message)
        require_value --message "${@:2}"
        message="$2"
        commit=1
        shift 2
        ;;
      --push)
        push=1
        shift
        ;;
      -h | --help)
        sync_usage
        return 0
        ;;
      *) die "sync: unknown argument ${arg}" ;;
    esac
  done

  repo_require

  local gitdir
  gitdir="$(git rev-parse --absolute-git-dir)"
  if [ -d "${gitdir}/rebase-merge" ] || [ -d "${gitdir}/rebase-apply" ]; then
    die "a rebase is already in progress; finish it with 'git rebase --continue' or 'git rebase --abort'"
  fi
  # Each of these leaves a half-applied tree that reads as an ordinary dirty
  # one, and --autostash on that state stashes a conflict.
  if [ -f "${gitdir}/CHERRY_PICK_HEAD" ]; then
    die "a cherry-pick is already in progress; finish it with 'git cherry-pick --continue' or 'git cherry-pick --abort'"
  fi
  if [ -f "${gitdir}/REVERT_HEAD" ]; then
    die "a revert is already in progress; finish it with 'git revert --continue' or 'git revert --abort'"
  fi
  if [ -f "${gitdir}/MERGE_HEAD" ]; then
    die "a merge is already in progress; finish it with 'git commit' or 'git merge --abort'"
  fi

  local branch
  branch="$(repo_current_branch)"
  [ -n "$branch" ] || die "HEAD is detached; check out a branch first"

  if repo_is_dirty; then
    if [ "$commit" = 1 ]; then
      sync_commit_tree "$message"
    elif [ "$autostash" = 0 ]; then
      git status --short >&2
      die "the working tree is dirty; --commit commits it, --autostash carries it across"
    fi
  fi

  repo_fetch

  local head head_ref
  head="$(repo_head_branch)"
  head_ref="$(repo_head_ref)"
  git rev-parse --verify --quiet "${head_ref}^{commit}" >/dev/null ||
    die "there is no $(ref_name "$head_ref") to move onto"

  if [ "$probe" = 1 ]; then
    [ "$squash" = 1 ] || die "--probe answers for --squash; pass both"
    [ "$branch" = "$head" ] &&
      die "--probe is about carrying a branch onto a new one; ${branch} is the head branch"
    sync_carry_verdict "$branch" "$head_ref"
    return 0
  fi

  if [ "$branch" = "$head" ]; then
    [ "$squash" = 1 ] &&
      die "--squash carries a branch onto a new one; ${branch} is the head branch"
    [ -n "$name" ] &&
      die "--branch names the branch a carry lands on; ${branch} is the head branch"
    sync_fast_forward "$head" "$head_ref" "$autostash"
    sync_report_conflicted_stash
    [ "$push" = 1 ] || return 0
    sync_push "$branch"
    return 0
  fi

  # A branch carrying nothing of its own is not finished, it is empty, and the
  # thing to do with it is the ordinary thing: leave it where it is, or move it
  # forward. Reading it as finished would start a new branch off one begun a
  # moment ago, and would refuse to push the branch the user is standing on.
  local counts ahead
  counts="$(repo_ahead_behind "refs/heads/${branch}" "$head_ref")"
  ahead="${counts%% *}"

  # What the branch is, asked of its content. A squash merge leaves no history
  # saying so, which is why this is the only question worth asking.
  local reason=''
  [ "${ahead:-0}" -gt 0 ] &&
    reason="$(merged_reason "$branch" "$head_ref" 2>/dev/null || printf '')"

  # How much of the branch the head branch already has. A squash merge of the
  # first few commits leaves the rest to move, and a rebase would replay all of
  # them and stop on the ones that are upstream in rewritten form.
  local boundary=''
  [ "${ahead:-0}" -gt 0 ] &&
    boundary="$(merged_absorbed_boundary "$branch" "$head_ref" 2>/dev/null || printf '')"

  if [ -n "$reason" ]; then
    sync_finished "$branch" "$head_ref" "$reason"
  elif [ "$squash" = 1 ]; then
    sync_carry_onto "$branch" "$head_ref" "$name" "$autostash"
  elif [ -n "$boundary" ]; then
    sync_pick_onto "$branch" "$head_ref" "$boundary" "$name"
  else
    [ -n "$name" ] &&
      die "${branch} is unfinished, so it is rebased in place and no new branch is named; pass --squash to carry it onto one"
    sync_rebase "$branch" "$head_ref" "$autostash"
  fi

  sync_report_conflicted_stash

  [ "$push" = 1 ] || return 0
  sync_push "$(repo_current_branch)"
}

# --------------------------------------------------------------------------
# Naming the next branch
# --------------------------------------------------------------------------

# Is this name spoken for, here or on the remote?
sync_name_taken() {
  local name="$1" remote
  if git show-ref --verify --quiet "refs/heads/${name}"; then
    return 0
  fi
  remote="$(repo_remote 2>/dev/null || printf '')"
  if [ -n "$remote" ] && git show-ref --verify --quiet "refs/remotes/${remote}/${name}"; then
    return 0
  fi
  return 1
}

# The name a carry lands on. It is typed, never generated: a name this command
# invented would be one more thing to explain to whoever reads the branch list.
#
# A `die` inside `$(…)` exits the subshell and nothing else, so a refusal
# written that way would print its message and let the command carry on with an
# empty name. This runs in the caller's own shell, where `die` still stops the
# program.
SYNC_NAME=''
sync_resolve_name() {
  local name="$1" why="$2"
  [ -n "$name" ] || die "${why}, so it needs a name: pass --branch <name>"
  if sync_name_taken "$name"; then
    die "there is already a branch called ${name}"
  fi
  SYNC_NAME="$name"
}

# --------------------------------------------------------------------------
# Committing what is in the tree
# --------------------------------------------------------------------------

# Tracked changes only, with a message somebody wrote.
#
# Staging an untracked file is how a .env or a build directory ends up in a
# commit, and nothing here can tell one of those from a file somebody meant to
# add. They are listed and left where they are.
sync_commit_tree() {
  local message="$1" tracked untracked
  tracked="$(git status --porcelain --untracked-files=no 2>/dev/null || printf '')"
  untracked="$(git ls-files --others --exclude-standard 2>/dev/null || printf '')"

  if [ -z "$tracked" ]; then
    if [ -n "$untracked" ]; then
      say 'Untracked, and left alone:'
      printf '%s\n' "$untracked" | indent_lines
      die "nothing tracked has changed; git add what you meant to keep"
    fi
    return 0
  fi

  say ''
  say 'To commit:'
  printf '%s\n' "$tracked" | indent_lines
  if [ -n "$untracked" ]; then
    say 'Untracked, and left alone:'
    printf '%s\n' "$untracked" | indent_lines
  fi

  [ -n "$message" ] || message="$(sync_ask_message)"
  [ -n "$message" ] || die "a commit needs a message"

  git_run commit --all --message "$message" || die "could not commit"
  [ "$ORIGIN_DRY_RUN" = 1 ] || good "committed $(git rev-parse --short HEAD)"
}

# The message, from the person at the terminal.
#
# `--yes` answers a question with a known answer, and this is not one. Nothing
# invents a commit message, so a run with no terminal says which flag carries
# one instead.
sync_ask_message() {
  local line
  if [ "$ORIGIN_ASSUME_YES" = 1 ] || ! have_tty; then
    die "a commit message cannot be asked for here; pass --message <text>"
  fi
  printf '\n%sMessage:%s ' "$C_BOLD" "$C_OFF" >&2
  IFS= read -r line </dev/tty || line=''
  printf '%s\n' "$line"
}

# --------------------------------------------------------------------------
# The rest of a partly absorbed branch
# --------------------------------------------------------------------------

# The head branch has the first commits of this branch already, in the one
# commit a squash merge made of them. The rest moves onto a new branch as
# itself: a cherry-pick keeps the commits, where a carry would flatten them.
#
# The branch it comes from is never moved, so a stop costs nothing.
sync_pick_onto() {
  local branch="$1" head_ref="$2" boundary="$3" name="$4"
  local base absorbed left status=0 empty=''

  base="$(git merge-base "$head_ref" "refs/heads/${branch}" 2>/dev/null || printf '')"
  absorbed="$(git rev-list --count "${base}..${boundary}" 2>/dev/null || printf '0')"
  left="$(git rev-list --count "${boundary}..refs/heads/${branch}" 2>/dev/null || printf '0')"

  if [ -z "$name" ]; then
    say ''
    note "$(ref_name "$head_ref") already has ${absorbed} commit(s) of ${branch}, squashed into one"
    say "  ${left} commit(s) after $(git rev-parse --short "$boundary") are not in it"
    say "  a rebase replays all $((absorbed + left)) and stops on the first ${absorbed}"
    say ''
    say 'Take the rest onto a new branch, commits kept:'
    say '  origin sync --branch <name>'
    say ''
    say 'Or as one commit:'
    say '  origin sync --squash --branch <name>'
    exit 1
  fi

  repo_is_dirty &&
    die "the working tree is dirty, and a cherry-pick has nowhere to put it; --commit commits it first"

  sync_resolve_name "$name" "the rest of ${branch} lands on a branch of its own"
  name="$SYNC_NAME"

  # An old git has no --empty, and a commit that turns out to add nothing stops
  # the pick there rather than being dropped.
  git cherry-pick -h 2>&1 | grep -q -- '--empty=' && empty='--empty=drop'

  confirm "Start ${name} from $(ref_name "$head_ref") and cherry-pick ${left} commit(s)?" \
    "git switch --create ${name} --no-track ${head_ref}" \
    "git cherry-pick ${empty:+${empty} }${boundary}..refs/heads/${branch}"

  git_run switch --create "$name" --no-track "$head_ref" ||
    die "could not create ${name} from $(ref_name "$head_ref")"

  if [ -n "$empty" ]; then
    git_run cherry-pick "$empty" "${boundary}..refs/heads/${branch}" || status=$?
  else
    git_run cherry-pick "${boundary}..refs/heads/${branch}" || status=$?
  fi
  [ "$status" = 0 ] || sync_report_pick_conflict "$branch" "$name"

  good "on ${name}, with ${left} commit(s) from ${branch}"
  say "  ${branch} is untouched, at $(git rev-parse --short "refs/heads/${branch}")"
}

# A cherry-pick that stopped. Every hunk in it is a genuine disagreement: the
# commits that were already upstream are behind the boundary and were never
# replayed.
sync_report_pick_conflict() {
  local branch="$1" name="$2" conflicted
  conflicted="$(git diff --name-only --diff-filter=U 2>/dev/null || printf '')"
  say ''
  warn "the cherry-pick onto ${name} stopped on a conflict"
  if [ -n "$conflicted" ]; then
    say 'Conflicted:'
    printf '%s\n' "$conflicted" | indent_lines
  fi
  say ''
  say 'Resolve them, then:'
  say '  git add <paths> && git cherry-pick --continue'
  say '  git cherry-pick --abort     put everything back'
  say ''
  say "${branch} has not moved, so nothing is at risk while you work."
  exit 1
}

# --------------------------------------------------------------------------
# The three shapes
# --------------------------------------------------------------------------

# On the head branch the only safe move is the one that cannot lose a commit.
sync_fast_forward() {
  local head="$1" head_ref="$2" autostash="$3" counts ahead flag=''

  counts="$(repo_ahead_behind "refs/heads/${head}" "$head_ref")"
  ahead="${counts%% *}"
  if [ "${ahead:-0}" -gt 0 ]; then
    say ''
    git --no-pager log --oneline "${head_ref}..refs/heads/${head}" >&2 || true
    say ''
    die "${head} has ${ahead} commit(s) that $(ref_name "$head_ref") does not; a fast-forward would lose them"
  fi

  [ "$autostash" = 1 ] && flag=' --autostash'
  confirm "Fast-forward ${head} to $(ref_name "$head_ref")?" "git merge --ff-only${flag} ${head_ref}"

  if [ "$autostash" = 1 ]; then
    git_run merge --ff-only --autostash "$head_ref" || die "could not fast-forward ${head}"
  else
    git_run merge --ff-only "$head_ref" || die "could not fast-forward ${head}"
  fi
  good "${head} is at $(ref_name "$head_ref")"
}

sync_rebase() {
  local branch="$1" head_ref="$2" autostash="$3" counts behind ahead status=0 flag='' before=''

  counts="$(repo_ahead_behind "refs/heads/${branch}" "$head_ref")"
  ahead="${counts%% *}"
  behind="${counts##* }"
  if [ "${behind:-0}" = 0 ]; then
    good "${branch} is already on top of $(ref_name "$head_ref")"
    return 0
  fi

  # A rebase writes new commits and moves the branch off the old ones. They
  # stay in the reflog, but only somebody who was told the sha can find them,
  # and only until it expires.
  before="$(git rev-parse --short "refs/heads/${branch}" 2>/dev/null || printf '')"
  losing "This will rewrite:" \
    "${ahead:-0} commit(s) on ${branch}, which becomes ${ahead:-0} new commit(s)" \
    "${branch} at ${before:-unknown} — restore with: git reset --keep ${before:-<sha>}"

  [ "$autostash" = 1 ] && flag=' --autostash'
  confirm "Rebase ${branch} onto $(ref_name "$head_ref")?" "git rebase${flag} ${head_ref}"

  if [ "$autostash" = 1 ]; then
    git_run rebase --autostash "$head_ref" || status=$?
  else
    git_run rebase "$head_ref" || status=$?
  fi

  [ "$status" = 0 ] || sync_report_rebase_conflict "$branch" "$head_ref"
  good "${branch} is on top of $(ref_name "$head_ref")"
  [ -n "$before" ] && say "  restore: git reset --keep ${before}"
  return 0
}

# The branch is finished: its change is in the head branch already, so there is
# nothing to rebase and nothing here to move. Starting the next branch is
# `origin new`, which fetches and branches off the head branch.
sync_finished() {
  local branch="$1" head_ref="$2" reason="$3" at=''
  at="$(git rev-parse --short "refs/heads/${branch}" 2>/dev/null || printf '')"
  say ''
  note "${branch} is ${reason} into $(ref_name "$head_ref"), so its commits cannot go back on top of it"
  say "  it is untouched${at:+, at ${at}}"
  say ''
  say 'Start the next change on a branch of its own:'
  say '  origin new <name>'
  exit 1
}

# Option (b): the whole change on a new branch off the head branch.
#
# `git merge --squash` from the new branch, so the two trees are compared with
# the fork point as the base. A rebase replays the branch commit by commit and
# stops on each one that no longer applies - including, after a squash merge
# upstream, on commits whose content the head branch already has. This stops at
# most once, and only where the two sides genuinely disagree.
#
# The old branch is never moved, so a stop here costs nothing.
sync_carry_onto() {
  local branch="$1" head_ref="$2" name="$3" autostash="$4"
  local status=0 sha count
  sync_resolve_name "$name" "carrying ${branch} onto a new branch"
  name="$SYNC_NAME"

  sha="$(git rev-parse --short "refs/heads/${branch}" 2>/dev/null || printf '')"
  count="$(git rev-list --count "${head_ref}..refs/heads/${branch}" 2>/dev/null || printf '0')"

  confirm "Carry ${branch} onto ${name}, from $(ref_name "$head_ref")?" \
    "git switch --create ${name} --no-track ${head_ref}" \
    "git merge --squash refs/heads/${branch}"

  sync_switch_new "$name" "$head_ref" "$autostash"

  git_run merge --squash "refs/heads/${branch}" || status=$?
  [ "$status" = 0 ] || sync_report_carry_conflict "$branch" "$name"

  if [ "$ORIGIN_DRY_RUN" = 1 ]; then
    good "would carry ${branch} onto ${name}"
    return 0
  fi

  if git diff --cached --quiet; then
    good "on ${name}, from $(ref_name "$head_ref")"
    say "  ${branch} had nothing $(ref_name "$head_ref") did not already have"
    say "  ${branch} is untouched${sha:+, at ${sha}}"
    return 0
  fi

  git_run commit --quiet --message "$(sync_carry_message "$branch" "$head_ref" "$count" "$sha")" ||
    die "the merge is staged on ${name} but the commit failed; commit it yourself"

  good "on ${name}, carrying ${branch} in one commit"
  say "  ${branch} is untouched${sha:+, at ${sha}}"
  say '  amend the message with: git commit --amend'
}

# What the commit says, which is what happened and nothing else. The message
# worth reading is the one the author writes over it.
sync_carry_message() {
  local branch="$1" head_ref="$2" count="$3" sha="$4"
  printf '%s, carried onto %s\n\nSquashed from %s commit(s) on %s%s.\n' \
    "$branch" "${head_ref##*/}" "${count:-0}" "$branch" "${sha:+ (${sha})}"
}

# --------------------------------------------------------------------------
# Would the carry apply cleanly?
# --------------------------------------------------------------------------

# Answered without touching the repository, so the question "one commit, or
# resolve these by hand?" can be put to somebody who already knows which of
# the two actually works.
#
# `git merge-tree --write-tree` performs the merge in the object database and
# writes nothing else - not the index, not the worktree, not a ref - so this is
# safe to ask in the middle of a conflicted rebase, which is exactly where it
# gets asked. Its answer is the objects alone: a conflicted index does not
# change it.
#
# `clean`, `conflicts`, or `unknown` when the git in hand is too old to say.
sync_carry_verdict() {
  local branch="$1" head_ref="$2" base status=0
  base="$(git merge-base "$head_ref" "refs/heads/${branch}" 2>/dev/null || printf '')"
  if [ -z "$base" ]; then
    printf 'unknown\n'
    return 0
  fi
  git merge-tree --write-tree --merge-base="$base" "$head_ref" "refs/heads/${branch}" \
    >/dev/null 2>&1 || status=$?
  case "$status" in
    0) printf 'clean\n' ;;
    1) printf 'conflicts\n' ;;
    # 129 is git rejecting the arguments, which is how a git without
    # `--write-tree` answers. Nothing is known, and saying so beats guessing.
    *) printf 'unknown\n' ;;
  esac
}

# --------------------------------------------------------------------------

# A conflict is a decision, and not this plugin's to make.
sync_report_rebase_conflict() {
  local branch="$1" head_ref="$2" conflicted
  conflicted="$(git diff --name-only --diff-filter=U 2>/dev/null || printf '')"
  say ''
  warn "the rebase of ${branch} onto $(ref_name "$head_ref") stopped on a conflict"
  if [ -n "$conflicted" ]; then
    say 'Conflicted:'
    printf '%s\n' "$conflicted" | indent_lines
  fi
  say ''
  say 'Resolve them, then:'
  say '  git rebase --continue    keep going'
  say '  git rebase --abort       put everything back'
  sync_offer_carry "$branch" "$head_ref"
  exit 1
}

# The other route, mentioned only where it is actually the better one.
#
# Advising a carry that would conflict too sends somebody down a second dead
# end and costs them the resolutions they had already made. So the offer is
# made on the verdict rather than on the hope, and it says what it costs: the
# individual commits become one, which is the whole of the trade.
sync_offer_carry() {
  local branch="$1" head_ref="$2" verdict count
  verdict="$(sync_carry_verdict "$branch" "$head_ref")"
  count="$(git rev-list --count "${head_ref}..refs/heads/${branch}" 2>/dev/null || printf '0')"
  case "$verdict" in
    clean)
      say ''
      say "$(ref_name "$head_ref") already has some of this, which is what the replay keeps"
      say "stopping on. The whole change applies to $(ref_name "$head_ref") cleanly as one"
      say "commit, at the cost of the ${count} commit(s) on ${branch} becoming one:"
      say '  git rebase --abort && origin sync --squash --branch <name>'
      ;;
    conflicts)
      say ''
      say "Carrying ${branch} onto a new branch would conflict here too, so these"
      say 'are genuine disagreements and resolving them is the way through.'
      ;;
  esac
}

# `git merge --squash` writes no MERGE_HEAD, so `git merge --abort` cannot back
# it out. `git reset --merge` is what does, and the branch it resets is the new
# one, which held nothing.
sync_report_carry_conflict() {
  local branch="$1" name="$2" conflicted
  conflicted="$(git diff --name-only --diff-filter=U 2>/dev/null || printf '')"
  say ''
  warn "carrying ${branch} onto ${name} stopped on a conflict"
  if [ -n "$conflicted" ]; then
    say 'Conflicted:'
    printf '%s\n' "$conflicted" | indent_lines
  fi
  say ''
  say 'This is one merge rather than a replay, so this is the only stop.'
  say 'Resolve them, then:'
  say '  git add <paths> && git commit    keep going'
  say "  git reset --merge                back out; ${branch} never moved"
  exit 1
}

# git's autostash re-applies by itself and says so quietly when it cannot.
sync_report_conflicted_stash() {
  local unmerged
  unmerged="$(git diff --name-only --diff-filter=U 2>/dev/null || printf '')"
  [ -n "$unmerged" ] || return 0
  say ''
  warn "the stashed changes did not re-apply cleanly; these files have conflict markers:"
  printf '%s\n' "$unmerged" | indent_lines
  say ''
  say "the stash is still there - 'git stash list' - so nothing is lost"
}

# Creating a branch and moving to it, carrying uncommitted work if asked.
#
# `git switch --create` refuses to move when a local change would be
# overwritten, so the stash is what makes --autostash mean the same thing here
# as it does for a rebase.
sync_switch_new() {
  local name="$1" start="$2" autostash="$3" stashed=0
  if [ "$autostash" = 1 ] && repo_is_dirty; then
    git_run stash push --include-untracked --message "origin sync" ||
      die "could not stash the working tree"
    stashed=1
  fi
  git_run switch --create "$name" --no-track "$start" ||
    die "could not create ${name} from $(ref_name "$start")"
  if [ "$stashed" = 1 ]; then
    git_run stash pop ||
      warn "the stash did not re-apply; it is still there - 'git stash list'"
  fi
}

# Which of the two pushes this is, decided by whether there is anything to
# lease against.
#
# Not by whether the branch has an upstream configured. A branch created by
# hand and pushed without `-u` has a remote-tracking ref and no upstream, and
# on that shape a plain push is refused the moment `sync` rebases it - which
# is a branch being brought up to date, not a name somebody else took. The
# remote-tracking ref is what the lease is evaluated against, so its presence
# is the question that decides.
sync_push() {
  local branch="$1" remote tracking
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$remote" ] || {
    note "there is no remote to push ${branch} to"
    return 0
  }

  tracking="refs/remotes/${remote}/${branch}"
  if git show-ref --verify --quiet "$tracking"; then
    sync_push_leased "$branch" "$remote" "$tracking"
  else
    sync_push_first "$branch" "$remote"
  fi
}

sync_push_leased() {
  local branch="$1" remote="$2" tracking="$3" before='' name="${2}/${1}"

  # The push replaces what the remote-tracking ref points at, and the pair of
  # lease flags means those commits are ones this clone had, so the sha below
  # is enough to put them back.
  before="$(git rev-parse --short "$tracking" 2>/dev/null || printf '')"
  losing "This will replace:" \
    "${name} at ${before:-unknown} — restore with: git push ${remote} ${before:-<sha>}:refs/heads/${branch}"

  confirm "Push ${branch} to ${name}?" \
    "git push --force-with-lease --force-if-includes --set-upstream ${remote} refs/heads/${branch}"

  if git_push_lease "$remote" "$branch"; then
    good "pushed ${branch}"
    [ -n "$before" ] && say "  restore: git push ${remote} ${before}:refs/heads/${branch}"
    return 0
  fi

  # The lease held or it did not. It did not, which means the branch on the
  # remote carries commits this clone never had - so it is somebody's work,
  # and not a copy of this branch left behind by an earlier push.
  say ''
  warn "${remote} refused ${branch}; ${name} carries commits this clone never had"
  say 'Look at what is there, or leave it alone and take another name:'
  say "  git log refs/remotes/${remote}/${branch}"
  say '  git branch -m <another name>'
  say '  origin sync --push --yes'
  exit 1
}

# The first push of a branch, which is a plain one.
#
# No lease and no force, deliberately. A lease is a claim about a ref this
# clone has seen, and on a first push there is none; `--force-if-includes`
# cannot be evaluated at all. More to the point, a generated name is a guess
# that somebody else may have guessed first - two agents syncing the same
# branch on the same day both arrive at `_001` - and the whole value of a plain
# push is that it is refused rather than granted when the name is taken.
#
# So the refusal is the answer, and the next number is the way through.
sync_push_first() {
  local branch="$1" remote="$2"

  confirm "Push ${branch} to ${remote}, as a new branch?" \
    "git push --set-upstream ${remote} refs/heads/${branch}"

  if git_run push --set-upstream "$remote" "refs/heads/${branch}"; then
    good "pushed ${branch} to ${remote}"
    say "  delete it again with: git push ${remote} --delete refs/heads/${branch}"
    return 0
  fi

  # There was no remote-tracking ref a moment ago, so a refusal means the
  # remote gained this branch since the last fetch: somebody else's, by
  # definition, and nothing of ours is in it.
  say ''
  warn "${remote} refused ${branch}; it already has a branch by that name"
  say 'Somebody got to the name first. Rename this one and push again:'
  say '  git branch -m <another name>'
  say '  origin sync --push --yes'
  exit 1
}
