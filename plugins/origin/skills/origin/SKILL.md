---
name: origin
description: Create, list and remove git worktrees; merge a pull request or merge request with a written body; put a branch back on top of the head branch, or start the next one when it cannot go back. Use when adding or cleaning up worktrees, merging a PR/MR, rebasing onto main, catching a branch up, starting the next branch after one was merged, deciding whether a branch is safe to delete, or diagnosing gh/glab authentication. Covers GitHub via gh and GitLab via glab; the worktree commands need neither.
---

# origin

Run `${CLAUDE_PLUGIN_ROOT}/bin/origin` instead of composing git commands
yourself. The failure modes here are silent and expensive, and this is where
they have already been handled.

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin --help
```

Every subcommand takes `--dry-run`, `--yes`, `--quiet` and `--verbose`; `gwl`
adds `--json`, and it is the only subcommand with machine-readable output.
Nothing reads from a terminal under `--yes`, so it never hangs. Commentary goes
to stderr and data to stdout, so `--json` and `--quiet` are always parseable.

## Printing means writing it in your own reply

Every instruction below to print, show or relay something means: put the text
in the message the user reads. Command output does not reach them — it is
shown to you. A `cat` of the file, an `echo`, or a pointer back to what the
CLI printed shows the user nothing at all.

So reproduce the lines. Never write "as above", "as printed above", or "see
the output" — there is nothing above from where the user is sitting. Somebody
asked to approve what they cannot see has not been asked.

## Before anything is deleted

Every destructive step prints a `This will delete:` block first — the path, the
files, the branch, the sha, and the command that puts each back. It prints
under `--yes` and `--quiet` as well. **Copy it into your reply.** It is the
only record of what went.

`--yes` answers for what git can restore: a branch delete that printed its
restore command, a rebase that is in the reflog, a merge that lives on the
forge. It does not answer for content git never tracked. A worktree holding
ignored files — `.env`, `node_modules/`, a build directory — stops even under
`--yes`, lists them, and names `--delete-ignored`. Show the user that list and
pass the flag only after they have agreed to those exact paths.

## Which one

| Wanted                      | Command                   |
| --------------------------- | ------------------------- |
| A worktree for a branch     | `origin gwa <branch>`     |
| What worktrees exist        | `origin gwl --json`       |
| Get rid of a finished one   | `origin gwr <branch>`     |
| Merge a pull request        | `origin merge [<number>]` |
| Catch a branch up with main | `origin renew`            |
| Start the next branch       | `origin renew --auto`     |
| Something is misconfigured  | `origin doctor`           |

`gwa`/`gwr`/`gwl` also spell out as `origin git-worktree add|remove|list` and
`origin gw add|remove|list`.

## Worktrees

They live at `<PARENT>/.worktrees/<branch>/<repo>`, where PARENT holds the main
checkout. Repositories side by side share the root, one directory each. A slash
in a branch name nests.

`gwa` fetches first, checks out an existing branch rather than failing, creates
new branches with `--no-track`, and refuses a destination owned by another
repository. Its last line of stdout is the path:

```bash
cd "$(origin gwa my-branch --quiet)"
```

`gwr` takes the branch or path to remove — there is no default — and removes it
**only when its branch is finished**: merged, squash-merged, or with a pull
request the forge calls merged or closed. A squash is the case git cannot see,
because it rewrites the commits; the script detects it by replaying the
branch's tree as one commit on the merge base and asking `git cherry` whether
that patch is upstream. An unfinished branch means the checkout stays, because
that is where the work is.

The branch is deleted only on git's own answer. The forge's is enough to drop
the checkout and no more, because a pull request says nothing about the commits
sitting on the local branch.

When it does delete a branch it prints `restore: git branch <name> <sha>`.
Relay that line. It is the undo, and it is the reason no flag is needed to
protect the branch.

`--force` removes the checkout of an unfinished branch, and **never deletes a
branch**. Do not pass it on your own initiative. It does not cover a worktree
holding uncommitted work: that is refused outright, with the uncommitted files
listed, because the checkout is the only place they exist.

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
question nobody can answer. `--auto` means the user has approved in advance:
write them out just the same, then merge without asking.

If `refusals` is non-empty — a draft, a conflict, a failing check, a protection
rule — say so and stop. `--force` is the user's to ask for.

## Renewing a branch

```bash
origin renew                      # rebase onto the head branch
origin renew --auto               # ...or start the next branch, when this one is finished
origin renew --squash --probe     # would the carry apply cleanly? changes nothing
origin renew --squash --auto      # carry the whole change onto a new branch
origin renew --push               # plain the first time, leased after
```

The route is decided by what the branch is. The one worth understanding is the
third: a branch whose change is already in the head branch **cannot be rebased
onto it**. A squash merge rewrites the branch into a single commit, so git has
no patch left to match, and a rebase replays work the head branch already has
and stops on it commit after commit. Those conflicts are not real and resolving
them is guesswork.

When `renew` says a branch is finished, do not reach for git. Re-run with
`--auto`, or `--branch <name>` if the user has a name. The old branch is left
exactly where it is.

When a **rebase** conflict stops you, do not start resolving. Ask which route
works first — `git rebase --abort` then `origin renew --squash --probe`, which
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
git config git-worktree-plugin.remote upstream   # which remote this repo belongs to
git config git-worktree-plugin.headBranch main   # which branch is the default
```

Both shared with the `git-worktree` zsh plugin. Nothing else is configurable:
the worktree root is always `<PARENT>/.worktrees`, and the forge is read from
the remote's host and, failing that, from what `gh` and `glab` are signed in to.
