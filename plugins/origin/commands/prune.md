---
name: prune
description: Say which worktrees are finished, and why, without removing any
argument-hint: "[--branch NAME] [--no-fetch] [--yes]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *)
---

Assess every worktree. Arguments: `$ARGUMENTS`

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin prune $ARGUMENTS
```

It fetches, clears git's bookkeeping for worktrees somebody deleted by hand,
and then prints one verdict per worktree. It removes nothing without `--yes`.

Three verdicts, and the third is not a softer second:

- **go** — finished, and safe to remove. The reason says how it was proved:
  `merged`, `squash-merged`, or a ref reaching a detached commit.
- **keep** — something says no. Uncommitted work, the head branch, a lock, the
  worktree you are standing in, ignored files, or a branch that is simply not
  merged.
- **unknown** — it could not tell. A branch with no upstream is the usual one:
  nothing says whether its commits were pushed anywhere.

Report the verdicts as they came. Never present `unknown` as `keep`, and never
offer `--yes` on a run that returned any `unknown` without saying which.

There is no `--dry-run`, because there is nothing to run dry: without `--yes`
this only reports. `--no-fetch` assesses from what is already here and says so;
the answer can be stale, which is the reason the fetch is the first step.
