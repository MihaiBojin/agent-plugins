---
name: gwr
description: Remove a finished worktree and delete its branch when it is merged
argument-hint: "<branch> | <path> [--force] [--delete-ignored]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *), Bash(git worktree list:*), Bash(git branch:*), Bash(git status:*)
---

Remove a worktree. Arguments: `$ARGUMENTS`

Show the dry run first:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin gwr $ARGUMENTS --dry-run
```

Then run it for real only if the user agrees:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin gwr $ARGUMENTS --yes
```

Name the worktree. There is no default: the branch you are on is either the
checkout you are standing in or the main worktree, and both are refused.

A branch counts as **finished** when git says it is merged, when it is
squash-merged — which the script detects by replaying the branch's tree onto
the merge base and asking `git cherry` whether that patch is already upstream —
or when the forge says its pull request is merged or closed.

The branch is **deleted** only on git's own answer, because only that one
compares the content and can say nothing would be lost. A pull request the
forge calls merged is enough to drop the checkout and no more.

- **The head branch** — the branch stays, whatever the merged test says. Its
  worktree is removed on the ordinary rules, and no restore line is printed
  because nothing was deleted. This one outranks the two below it.
- **Finished, and git can prove it** — the worktree goes and the branch goes
  with it. The output carries `restore: git branch <name> <sha>`; copy that
  line, it is the undo.
- **Finished on the forge** — the worktree goes, the branch stays.
- **Not finished** — it refuses, because the checkout is where that work lives.
- **Detached** — no branch, so what counts is whether some ref already reaches
  its commit. One that does: the worktree goes. None: refused, and `--force`
  removes it and prints `git worktree add --detach <path> <sha>` as the undo.
- **`--force`** — removes the checkout of an unfinished branch and **keeps the
  branch**. Never pass it on your own initiative; the refusal is the point.

Uncommitted changes, stashes on the branch, a lock, the main worktree and the
one you are standing in are all refused with the reason printed. **Uncommitted
changes are refused outright — `--force` does not override that one**, because
the checkout is the only copy. Relay the reason. Do not go around it with git.

## What it says before it deletes anything

Every run prints a `This will delete:` block naming the worktree path, any
ignored files inside it, and the branch with its sha and restore command. It
prints under `--yes` and `--quiet` too. **Copy that block into your reply.**
The user does not see command output, so a block left in the terminal is a
deletion nobody was told about.

Ignored files — `.env`, `node_modules/`, a build directory — are deleted along
with the checkout by git itself, and nothing restores them. So:

- If the worktree holds any, the command **stops even under `--yes`**, lists
  them, and names `--delete-ignored`.
- Copy that list into your reply and ask. Pass `--delete-ignored` only after they
  have said yes to those exact paths. Never add it on your own initiative, and
  never pre-emptively.
