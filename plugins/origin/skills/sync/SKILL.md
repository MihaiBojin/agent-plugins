---
name: sync
description: Fetch, put this branch back on top of the head branch, and push it with a lease
argument-hint: "[--branch <name>] [--squash] [--commit | --message <text>] [--push]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *), Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git rebase --continue), Bash(git rebase --abort), Bash(git reset --merge), Bash(git branch:*), Read, Edit, AskUserQuestion
---

In Codex, `$ARGUMENTS` means the arguments supplied with the skill. Substitute
them before running a command; do not read them from a shell variable.
Resolve `${CLAUDE_PLUGIN_ROOT}` to the plugin root, two directories above this
`SKILL.md`, if the client has not expanded it. Run the resulting absolute
script path from the repository being worked on.

Bring the current branch up to date. Arguments: `$ARGUMENTS`

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin sync $ARGUMENTS --yes
```

It fetches, resolves the head branch, and picks a route from what the branch
is. Nothing here runs `git reset --hard`.

## What it comes back with

- **Succeeded.** Say so in one line, and name the branch you are now on.
- **Refuses because the tree is dirty.** List what is uncommitted in your
  reply, since the user does not see command output. Two ways on, and both are
  the user's to pick: `--autostash` carries it across, and
  `--message <text>` commits the tracked changes first. Write the message
  yourself from the diff, show it, and pass it only once they agree. Untracked
  files are never staged; the command lists them and leaves them.
- **Refuses because the head branch has local commits.** Those commits are the
  finding. Write them out in your reply and ask. Do not discard them.
- **Refuses because part of the branch is already upstream.** Its pull request
  was merged and work carried on afterwards, so the head branch holds the first
  commits in squashed form. It names how many are absorbed and how many are
  left, and stops before a rebase that would replay the absorbed ones. Put the
  choice to the user and give it a name:

  - `origin sync --branch <name> --yes` cherry-picks the commits after the
    boundary onto a new branch, keeping them as they are.
  - `origin sync --squash --branch <name> --yes` carries the whole difference
    as one commit instead.

  Either way the old branch does not move. A stopped cherry-pick is yours to
  resolve, and every hunk in it is genuine: the absorbed commits were never
  replayed.

- **Refuses because the branch is finished.** Its change is already in the head
  branch, so its commits cannot go back on top of it. The next change starts on
  a branch of its own: `origin new-branch <name>` with a name the user chooses,
  or `origin rotate` to continue the chain. Say that this branch is untouched.
- **Stopped on a conflict.** Below.

## A conflict is yours to try

Resolving conflicts is ordinary work you can do — as yourself, reading the
files. Never `git rebase --skip`, and never abort except as described here.

**A rebase conflict.** Do not start resolving. Find out first whether the other
route works, because when it does the resolutions you would have made are
wasted work on content that is already upstream:

```bash
git rebase --abort
${CLAUDE_PLUGIN_ROOT}/bin/origin sync --squash --probe --yes
```

It prints one word and changes nothing.

- **`clean`** — the whole change applies to the head branch as one commit.
  **Ask the user**, every time, and do not decide this yourself:

  - **Carry it as one commit** — the conflicts go away, and the _N_ individual
    commits on the branch become one. Name the number.
  - **Resolve the rebase by hand** — the commits are kept and you work through
    the conflicts.

  Say what is behind the choice: the head branch already has some of this, so
  the rebase is replaying work that is upstream and will keep stopping on it.
  On **Carry**, ask for a name and run
  `origin sync --squash --branch <name> --yes`. On **Resolve**, re-run
  `origin sync --yes` to get back to the conflict and work through it.

- **`conflicts`** — no route avoids it. Say so and resolve the rebase by hand:
  re-run `origin sync --yes`, resolve, `git add` the paths,
  `git rebase --continue`, and keep going through any further stops.

- **`unknown`** — git here is too old to answer. Say so and resolve by hand.

**A carry conflict**, from `--squash`. This is one merge, not a replay, so it
is the only stop and everything in it is a genuine disagreement. Resolve it,
`git add` the paths, and `git commit`. The branch you came from has not moved,
so nothing is at risk while you work.

**When you are not confident.** Do not guess at a resolution and do not leave
the repository mid-operation. Back out — `git rebase --abort`, or
`git reset --merge` for a carry — and tell the user which files conflicted,
what the two sides were trying to do, and what you could not decide between.

## Naming

A carry lands on a branch the user names, and `--branch <name>` is the only way
to give it one. Nothing here invents a branch name.

## Pushing

`--push` is opt-in and picks its own push. A branch the remote already has goes
with `--force-with-lease --force-if-includes`, and the output carries the sha
it replaced beside the command that puts it back. Copy both into your reply. A
branch the remote has never seen goes plainly.

Neither is refused for ordinary reasons: a branch pushed by hand without `-u`,
or one `sync` has just rebased, pushes. A refusal means the branch on the
remote carries commits this clone never had. Do exactly what it says:

```bash
git branch -m <another name>
${CLAUDE_PLUGIN_ROOT}/bin/origin sync --push --yes
```

Tell the user which name the branch ended up with.
