---
name: gwl
description: List every worktree with its branch, drift, state and pull request
argument-hint: "[--json]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *), Bash(git worktree list:*)
---

List the worktrees. Arguments: `$ARGUMENTS`

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin gwl --json
```

Use `--json` when you need to act on the answer; it carries the absolute
`path`, so you can change directory without deriving it. Each entry has `name`,
`path`, `branch`, `ahead`, `behind`, `dirty`, `current`, `pr` and `age`.

Drop `--json` when the user just wants to look — the table is better than
anything you would render from the JSON.

If the user is choosing one to work in, show the table and ask which. Do not
guess from a branch name that sounds relevant.
