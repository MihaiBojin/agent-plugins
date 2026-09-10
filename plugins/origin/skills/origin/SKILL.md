---
name: origin
description: Start a branch off a freshly fetched head branch; commit a session's work and open the pull request, stacked when it has layers; put a branch back on top of the head branch and push it with a lease; merge a pull request or merge request with a body written from the change. Use when starting a branch, opening or stacking a PR/MR, rebasing onto main, catching a branch up, or merging. Covers GitHub via gh and GitLab via glab. Worktrees are not here: gwa, gwr, gwl and gwm are shell commands the user runs.
user-invocable: false
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *), Bash(git worktree list:*), Bash(git status:*), Bash(git branch:*)
---

# origin

Run `${CLAUDE_PLUGIN_ROOT}/bin/origin` instead of composing git commands
yourself. The failure modes here are silent and expensive, and this is where
they have already been handled.

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin --help
```

Every subcommand takes `--dry-run`, `--yes`, `--quiet` and `--verbose`. Nothing
reads from a terminal under `--yes`, so it never hangs. Commentary goes to
stderr and data to stdout, so `--quiet` is always parseable.

Worktrees are not here. `gwa`, `gwr`, `gwl` and `gwm` are shell commands the
user runs in a terminal; if a session needs one, say so rather than reaching
for `git worktree` yourself.

## Printing means writing it in your own reply

Every instruction below to print, show or relay something means: put the text
in the message the user reads. Command output does not reach them — it is
shown to you. A `cat` of the file, an `echo`, or a pointer back to what the
CLI printed shows the user nothing at all.

So reproduce the lines. Never write "as above", "as printed above", or "see
the output" — there is nothing above from where the user is sitting. Somebody
asked to approve what they cannot see has not been asked.

## Before anything is replaced

Nothing here deletes a branch or a worktree. What it does replace, it prints
first: a rebase moves the branch off the commits it was on, and a leased push
replaces what the remote holds. Both print a `This will replace:` block naming
the sha and the command that puts it back, under `--yes` and `--quiet` as well.
**Copy it into your reply.** It is the only record of where the branch was.

`--yes` answers for what git can restore: a rebase that is in the reflog, a
push whose old sha was printed, a merge that lives on the forge. Say what it
answered for.

## Which one

| Wanted                      | Command                    |
| --------------------------- | -------------------------- |
| A branch for new work       | `origin new [<name>]`      |
| Open a pull request         | [pr skill](../pr/SKILL.md) |
| Catch a branch up with main | `origin sync`              |
| Push it afterwards          | `origin sync --push`       |
| Merge a pull request        | `origin merge [<number>]`  |

## Starting a branch

```bash
origin new <name>
```

It fetches, then branches off the head branch as the remote has it, with
`--no-track` so `git push` cannot target the head branch. It refuses a name
that is already a branch and a name git will not take.

Give it a name whenever the work has one - that is the name the user and every
reviewer will see. With no name it derives `<branch>-YYYY-MM-DD_NNN` from the
branch you are standing on, which is the continuation case: this branch is
finished and the next change carries on from it. From the head branch it asks
for a name instead.

## Opening one

There is no subcommand for this. It is git and the forge CLI, so nothing
refuses on your behalf and `--force` is never the answer to a step that failed.
It is repeatable: check what has already happened before each step, and a
second run on a branch whose pull request is open does nothing.

1. Read `git status --short` and `git diff`. Say what the change does, and
   whether it is one change or several. Anything the session did not touch is
   somebody else's: list those paths and ask before staging one. Never
   `git add -A`.
2. On the head branch, `git switch --create <name>`, named after the change.
   On any other branch, that is the branch.
3. Several layers stack by their base branches and nothing else: the first
   branches off the head branch, each later one off the branch before it, and
   each pull request is based on its parent. Take one layer all the way to an
   open pull request before starting the next.
4. Stage by path and commit per layer. `origin sync --message <text>` commits
   a dirty tree when that is all that is in the way; it takes tracked changes
   only and never stages an untracked file. The message says what the change does,
   not how the session went. A decision file under `.claude/decisions/` goes in
   with the work it explains.
5. Push the way `sync` does: `git push --set-upstream <remote>
refs/heads/<branch>` when the remote-tracking ref does not exist, and
   `git push --force-with-lease --force-if-includes --set-upstream ...` when it
   does. A refused first push means the name is taken: rename and push. A
   refused leased push means somebody else's commits are there; stop.
6. Write the title and body in your reply, ask, then `gh pr create --base
<parent>` or `glab mr create --target-branch <parent>`.
7. On GitHub, once every one is open,
   `gh extension list | grep -q gh-stack && gh stack link` teaches GitHub the
   chain. Best effort: never install the extension, never mention it on GitLab
   or where it does not work, and never let it failing change what was filed.

## Merging

Two steps, in order:

```bash
origin merge --gather                      # JSON: pr, commits, diffstat, trailers, refusals
origin merge --body-file <path> --yes      # after the user has approved the body
```

`--gather` is the material; you write the body. The default squash body on both
forges is the commit list, which records how the work happened rather than what
it did, and the commit landing on the head branch has to survive without the
pull request beside it.

- One line stating the change, imperative mood.
- Three to five bullets on what changed and why, not one per commit.
- Drop `wip`, `fixup!`, `address review comments`, lint and formatting commits.
- Never invent a rationale that is not in the description or the diff.
- 72 columns, no headings, no preamble.
- Leave the trailers alone: `origin` re-attaches every `Fixes #123` and
  `Co-authored-by:` afterwards.

Write the title and body out in your reply, in full, and let the user edit
either before merging. An agent session has no terminal, so run the merge with
`--yes` once they approve — without it the script refuses rather than asking a
question nobody can answer. A `--yes` the user typed themselves is approval in
advance: write them out just the same, then merge without asking.

If `refusals` is non-empty — a draft, a conflict, a failing check, a check
still running, a protection rule — say so and stop. `--force` is the user's to
ask for.

An unfinished check is the one refusal worth offering to wait out. `origin`
never waits: re-run `--gather` every 30 seconds until `refusals` empties, then
merge the body they already approved. Stop the moment a check fails. Poll only
when the user asked for it.

## Catching a branch up

```bash
origin sync                              # rebase onto the head branch
origin sync --branch <name>              # ...or take the unabsorbed rest onto a new branch
origin sync --squash --probe             # would the carry apply cleanly? changes nothing
origin sync --squash --branch <name>     # carry the whole change onto a new branch
origin sync --push                       # plain the first time, leased after
```

The route is decided by what the branch is. The one worth understanding is the
third: a branch whose change is already in the head branch **cannot be rebased
onto it**. A squash merge rewrites the branch into a single commit, so git has
no patch left to match, and a rebase replays work the head branch already has
and stops on it commit after commit. Those conflicts are not real and resolving
them is guesswork.

When `sync` says the head branch already has part of the branch, it has found
a squash-merged pull request with work added after it. A rebase would replay
the absorbed commits and stop on each one. `origin sync --branch <name>`
cherry-picks what is left onto a new branch and keeps the commits;
`--squash --branch <name>` makes it one commit. The old branch never moves.

When `sync` says a branch is finished, do not reach for git. The next change
starts on a branch of its own: `origin new <name>`, with a name the user picks,
or a bare `origin new` to take `<branch>-YYYY-MM-DD_NNN`. The old branch is
left exactly where it is.

When a **rebase** conflict stops you, do not start resolving. Ask which route
works first — `git rebase --abort` then `origin sync --squash --probe`, which
prints one word and changes nothing:

- `clean` — the carry works. **Put it to the user**: carry the change as one
  commit and lose the individual commits, or resolve the rebase by hand and
  keep them. Never pick for them.
- `conflicts` — no route avoids it. Resolve the rebase.
- `unknown` — git is too old to say. Resolve the rebase.

A **carry** conflict, from `--squash`, is the only stop there will be, and
every hunk in it is a genuine disagreement. Resolve it, `git add`, `git commit`.
The branch it came from never moved. `git merge --abort` does not back a carry
out; `git reset --merge` does.

`--push` picks its own push. A branch the remote already has goes with
`--force-with-lease --force-if-includes`, which accepts a branch this clone
rebased and refuses one carrying somebody else's commits. A branch the remote
has never seen goes plainly, so a generated name somebody else took is refused
rather than overwritten.

Either refusal names the next free number. Do what it says —
`git branch -m <that name>`, then push again — and tell the user which name the
branch ended up with. A branch pushed by hand without `-u` needs none of this:
it pushes.

## What it refuses, so do not ask it to

`git reset --hard`, `git clean --force`, a bare `--force` push, a force delete
of a branch not proved merged — `-D`, `-d -f` and `--delete --force` alike —
and `git worktree remove --force` in any circumstance. These live in
`lib/common.sh`, not in each command, and they are absolute: no flag reaches
them, `--yes` included.

The script also never resolves a conflict. You may, as yourself, reading the
files — never with `git rebase --skip`, and never by abandoning the repository
part-way through.

If a refusal is in your way, relay what it said. Do not run the git command
yourself — that is the thing this plugin exists to stop.

## Configuration

```bash
git config checkout.defaultRemote upstream   # which remote this repo belongs to
git remote set-head upstream --auto          # which branch is the default
```

Both are git's own, so the `git-worktree` shell commands read the same answer,
and a single-remote clone needs neither. Nothing else is configurable: the
forge is read from the remote's host and, failing that, from what `gh` and
`glab` are signed in to.
