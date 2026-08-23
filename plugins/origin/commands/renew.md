---
name: renew
description: Put this branch back on top of the head branch, or start the next one
argument-hint: "[--squash] [--auto | --branch <name>] [--autostash] [--push]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *), Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git rebase --continue), Bash(git rebase --abort), Bash(git reset --merge), Bash(git branch:*), Read, Edit, AskUserQuestion
---

Bring the current branch up to date. Arguments: `$ARGUMENTS`

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin renew $ARGUMENTS --yes
```

It fetches, resolves the head branch, and takes one of three routes depending
on what the branch is. Nothing here runs `git reset --hard`.

## What it comes back with

- **Succeeded.** Say so in one line, and name the branch you are now on.
- **Refuses because the tree is dirty.** List what is uncommitted in your
  reply, since the user does not see command output. Offer
  `--autostash`. Do not commit on the user's behalf.
- **Refuses because the head branch has local commits.** Those commits are the
  finding. Write them out in your reply and ask. Do not discard them.
- **Refuses because the branch is finished.** Its change is already in the head
  branch, so its commits cannot go back on top of it and the next change needs
  a branch of its own. Re-run with `--auto`, or with `--branch <name>` if the
  user has a name in mind. Say which branch you started and that the old one is
  untouched.
- **Stopped on a conflict.** Below.

## A conflict is yours to try

Resolving conflicts is ordinary work you can do — as yourself, reading the
files. Never `git rebase --skip`, and never abort except as described here.

**A rebase conflict.** Do not start resolving. Find out first whether the other
route works, because when it does the resolutions you would have made are
wasted work on content that is already upstream:

```bash
git rebase --abort
${CLAUDE_PLUGIN_ROOT}/bin/origin renew --squash --probe --yes
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
  On **Carry**, run `origin renew --squash --auto --yes`. On **Resolve**, re-run
  `origin renew --yes` to get back to the conflict and work through it.

- **`conflicts`** — no route avoids it. Say so and resolve the rebase by hand:
  re-run `origin renew --yes`, resolve, `git add` the paths,
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

`--auto` names the next branch `<branch>-YYYY-MM-DD_NNN`, taking the first free
number for today. Renewing an already-renewed branch replaces the suffix rather
than adding a second one. Pass `--branch <name>` when the user gives a name.

## Pushing

`--push` is opt-in and picks its own push. A branch the remote already has goes
with `--force-with-lease --force-if-includes`, and the output carries the sha
it replaced beside the command that puts it back. Copy both into your reply. A
branch the
remote has never seen goes plainly.

Neither is refused for ordinary reasons: a branch pushed by hand without `-u`,
or one `renew` has just rebased, pushes. A refusal means the branch on the
remote carries commits this clone never had, and the output names the next free
number. Do exactly what it says:

```bash
git branch -m <the name it named>
${CLAUDE_PLUGIN_ROOT}/bin/origin renew --push --yes
```

Repeat if that is refused too, and tell the user which name the branch ended up
with.
