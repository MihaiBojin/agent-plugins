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

renew_usage() {
  cat >&2 <<'USAGE'
origin renew [flags]

  Put this branch back on top of the head branch, or start the next one.

  A branch whose change is already in the head branch cannot be rebased onto
  it, so renew starts a new branch instead and leaves this one alone.

  --branch <name>   Name for the new branch
  --auto            Name it after this one: <branch>-YYYY-MM-DD_NNN
  --squash          Do not rebase; carry the whole change onto a new branch
  --probe           With --squash: say whether it would apply cleanly, and stop
  --autostash       Stash before and re-apply after, via git's own
  --push            Push afterwards: plain for a new branch, leased for a known one
  --dry-run         Say what would happen
  --yes             Do not ask
USAGE
}

renew_main() {
  local autostash=0 push=0 squash=0 probe=0 name='' auto=0 arg
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
      --auto)
        auto=1
        shift
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
      --push)
        push=1
        shift
        ;;
      -h | --help)
        renew_usage
        return 0
        ;;
      *) die "renew: unknown argument ${arg}" ;;
    esac
  done

  [ -n "$name" ] && [ "$auto" = 1 ] &&
    die "--branch and --auto both name the new branch; pass one"

  repo_require

  local gitdir
  gitdir="$(git rev-parse --absolute-git-dir)"
  if [ -d "${gitdir}/rebase-merge" ] || [ -d "${gitdir}/rebase-apply" ]; then
    die "a rebase is already in progress; finish it with 'git rebase --continue' or 'git rebase --abort'"
  fi

  local branch
  branch="$(repo_current_branch)"
  [ -n "$branch" ] || die "HEAD is detached; check out a branch first"

  if repo_is_dirty && [ "$autostash" = 0 ]; then
    git status --short >&2
    die "the working tree is dirty; commit it, or pass --autostash"
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
    renew_carry_verdict "$branch" "$head_ref"
    return 0
  fi

  if [ "$branch" = "$head" ]; then
    [ "$squash" = 1 ] &&
      die "--squash carries a branch onto a new one; ${branch} is the head branch"
    [ -n "$name" ] || [ "$auto" = 1 ] &&
      die "a new branch is for continuing work; ${branch} is the head branch"
    renew_fast_forward "$head" "$head_ref" "$autostash"
    renew_report_conflicted_stash
    [ "$push" = 1 ] || return 0
    renew_push "$branch"
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

  if [ -n "$reason" ]; then
    renew_start_next "$branch" "$head_ref" "$reason" "$name" "$auto" "$autostash"
  elif [ "$squash" = 1 ]; then
    renew_carry_onto "$branch" "$head_ref" "$name" "$auto" "$autostash"
  else
    [ -n "$name" ] || [ "$auto" = 1 ] &&
      die "${branch} is unfinished, so it is rebased in place and no new branch is named; pass --squash to carry it onto one"
    renew_rebase "$branch" "$head_ref" "$autostash"
  fi

  renew_report_conflicted_stash

  [ "$push" = 1 ] || return 0
  renew_push "$(repo_current_branch)"
}

# --------------------------------------------------------------------------
# Naming the next branch
# --------------------------------------------------------------------------

# The stem a generated name is built from: this branch with any suffix a
# previous --auto added taken off, so renewing four times gives four names
# rather than one name four suffixes long.
renew_stem() {
  printf '%s\n' "$1" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{3}$//'
}

# Is this name spoken for, here or on the remote?
renew_name_taken() {
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

# <stem>-YYYY-MM-DD_NNN, at the first number free today.
#
# Three digits, so the sequence cannot be read as another field of the date the
# way a two-digit one beside -08-23 can.
renew_auto_name() {
  local stem date candidate n=1
  stem="$(renew_stem "$1")"
  date="$(date +%Y-%m-%d)"
  while [ "$n" -lt 1000 ]; do
    candidate="$(printf '%s-%s_%03d' "$stem" "$date" "$n")"
    if ! renew_name_taken "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    n=$((n + 1))
  done
  return 1
}

# The name the new branch gets, into a variable rather than down a pipe.
#
# A `die` inside `$(…)` exits the subshell and nothing else, so a refusal
# written that way would print its message and let the command carry on with an
# empty name. This runs in the caller's own shell, where `die` still stops the
# program.
RENEW_NAME=''
renew_resolve_name() {
  local branch="$1" name="$2" auto="$3" why="$4"
  if [ -z "$name" ]; then
    if [ "$auto" != 1 ]; then
      die "${branch} ${why}, so the next change needs a branch of its own; pass --branch <name> or --auto"
    fi
    name="$(renew_auto_name "$branch")" ||
      die "every name derived from ${branch} is taken today; pass --branch <name>"
  fi
  if renew_name_taken "$name"; then
    die "there is already a branch called ${name}"
  fi
  RENEW_NAME="$name"
}

# --------------------------------------------------------------------------
# The three shapes
# --------------------------------------------------------------------------

# On the head branch the only safe move is the one that cannot lose a commit.
renew_fast_forward() {
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

renew_rebase() {
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

  [ "$status" = 0 ] || renew_report_rebase_conflict "$branch" "$head_ref"
  good "${branch} is on top of $(ref_name "$head_ref")"
  [ -n "$before" ] && say "  restore: git reset --keep ${before}"
  return 0
}

# The branch is finished. Nothing is moved; the next change gets a branch.
renew_start_next() {
  local branch="$1" head_ref="$2" reason="$3" name="$4" auto="$5" autostash="$6" at=''
  renew_resolve_name "$branch" "$name" "$auto" "is ${reason} into $(ref_name "$head_ref")"
  name="$RENEW_NAME"

  say ''
  note "${branch} is ${reason} into $(ref_name "$head_ref"), so its commits cannot go back on top of it"
  confirm "Start ${name} from $(ref_name "$head_ref")?" \
    "git switch --create ${name} --no-track ${head_ref}"

  renew_switch_new "$name" "$head_ref" "$autostash"
  at="$(git rev-parse --short "refs/heads/${branch}" 2>/dev/null || printf '')"
  good "on ${name}, from $(ref_name "$head_ref")"
  say "  ${branch} is untouched${at:+, at ${at}}"
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
renew_carry_onto() {
  local branch="$1" head_ref="$2" name="$3" auto="$4" autostash="$5"
  local status=0 sha count
  renew_resolve_name "$branch" "$name" "$auto" 'is being carried onto a new branch'
  name="$RENEW_NAME"

  sha="$(git rev-parse --short "refs/heads/${branch}" 2>/dev/null || printf '')"
  count="$(git rev-list --count "${head_ref}..refs/heads/${branch}" 2>/dev/null || printf '0')"

  confirm "Carry ${branch} onto ${name}, from $(ref_name "$head_ref")?" \
    "git switch --create ${name} --no-track ${head_ref}" \
    "git merge --squash refs/heads/${branch}"

  renew_switch_new "$name" "$head_ref" "$autostash"

  git_run merge --squash "refs/heads/${branch}" || status=$?
  [ "$status" = 0 ] || renew_report_carry_conflict "$branch" "$name"

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

  git_run commit --quiet --message "$(renew_carry_message "$branch" "$head_ref" "$count" "$sha")" ||
    die "the merge is staged on ${name} but the commit failed; commit it yourself"

  good "on ${name}, carrying ${branch} in one commit"
  say "  ${branch} is untouched${sha:+, at ${sha}}"
  say '  amend the message with: git commit --amend'
}

# What the commit says, which is what happened and nothing else. The message
# worth reading is the one the author writes over it.
renew_carry_message() {
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
renew_carry_verdict() {
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
renew_report_rebase_conflict() {
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
  renew_offer_carry "$branch" "$head_ref"
  exit 1
}

# The other route, mentioned only where it is actually the better one.
#
# Advising a carry that would conflict too sends somebody down a second dead
# end and costs them the resolutions they had already made. So the offer is
# made on the verdict rather than on the hope, and it says what it costs: the
# individual commits become one, which is the whole of the trade.
renew_offer_carry() {
  local branch="$1" head_ref="$2" verdict count
  verdict="$(renew_carry_verdict "$branch" "$head_ref")"
  count="$(git rev-list --count "${head_ref}..refs/heads/${branch}" 2>/dev/null || printf '0')"
  case "$verdict" in
    clean)
      say ''
      say "$(ref_name "$head_ref") already has some of this, which is what the replay keeps"
      say "stopping on. The whole change applies to $(ref_name "$head_ref") cleanly as one"
      say "commit, at the cost of the ${count} commit(s) on ${branch} becoming one:"
      say '  git rebase --abort && origin renew --squash --auto'
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
renew_report_carry_conflict() {
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
renew_report_conflicted_stash() {
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
renew_switch_new() {
  local name="$1" start="$2" autostash="$3" stashed=0
  if [ "$autostash" = 1 ] && repo_is_dirty; then
    git_run stash push --include-untracked --message "origin renew" ||
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
# on that shape a plain push is refused the moment `renew` rebases it - which
# is a branch being brought up to date, not a name somebody else took. The
# remote-tracking ref is what the lease is evaluated against, so its presence
# is the question that decides.
renew_push() {
  local branch="$1" remote tracking
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$remote" ] || {
    note "there is no remote to push ${branch} to"
    return 0
  }

  tracking="refs/remotes/${remote}/${branch}"
  if git show-ref --verify --quiet "$tracking"; then
    renew_push_leased "$branch" "$remote" "$tracking"
  else
    renew_push_first "$branch" "$remote"
  fi
}

renew_push_leased() {
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
  say 'Look at what is there, or leave it alone and take the next name:'
  say "  git log refs/remotes/${remote}/${branch}"
  renew_say_next_name "$branch"
  exit 1
}

# The first push of a branch, which is a plain one.
#
# No lease and no force, deliberately. A lease is a claim about a ref this
# clone has seen, and on a first push there is none; `--force-if-includes`
# cannot be evaluated at all. More to the point, a generated name is a guess
# that somebody else may have guessed first - two agents renewing the same
# branch on the same day both arrive at `_001` - and the whole value of a plain
# push is that it is refused rather than granted when the name is taken.
#
# So the refusal is the answer, and the next number is the way through.
renew_push_first() {
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
  say 'Somebody got to the name first. Take the next one:'
  renew_say_next_name "$branch"
  exit 1
}

# The next free number, after finding out what the remote actually holds.
renew_say_next_name() {
  local branch="$1" remote next=''
  remote="$(repo_remote 2>/dev/null || printf '')"
  [ -n "$remote" ] && git fetch "$remote" --prune --quiet 2>/dev/null
  next="$(renew_auto_name "$branch" 2>/dev/null || printf '')"
  say "  git branch -m ${next:-<another name>}"
  say '  origin renew --push --yes'
}
