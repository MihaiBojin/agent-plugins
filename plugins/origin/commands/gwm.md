---
name: gwm
description: Rename this worktree's branch and move its checkout so the two agree
argument-hint: "<new-branch> [--yes]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *)
---

Rename the branch checked out here. Arguments: `$ARGUMENTS`

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin gwm $ARGUMENTS
```

Directory name equals branch name is the invariant every other command reads,
so this renames the branch and moves the checkout as one step. Doing either
alone leaves a worktree whose directory says one thing and whose HEAD says
another, which `gwl` and `gwr` both read wrong.

It refuses rather than guessing: the main worktree, a detached checkout, a
locked one, a name a branch already has, and a destination that is taken or
belongs to another repository.

The new path is on stdout. Report it — the shell that called this is still
standing in the old one, and a subprocess cannot `cd` its parent.
