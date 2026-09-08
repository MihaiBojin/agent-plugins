---
name: gwa
description: Add a git worktree for a branch and print its path
argument-hint: "<branch> [--base <ref>]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *), Bash(git worktree list:*), Bash(git branch:*)
---

Add a worktree. Arguments: `$ARGUMENTS`

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin gwa $ARGUMENTS
```

It fetches first so a new branch starts from a current head branch, checks out
an existing branch instead of failing, creates new branches with `--no-track`
so `git push` cannot target the head branch, and refuses a destination that
belongs to another repository or to another worktree of this one, naming the
branch it found there.

The worktree lands at `<PARENT>/.worktrees/<branch>/<repo>`, where PARENT holds
the main checkout. A slash in the branch name nests.

**The last line of stdout is the path, and nothing else is on stdout:**

```bash
cd "$(${CLAUDE_PLUGIN_ROOT}/bin/origin gwa <branch> --quiet)"
```

Tell the user the path. If they meant to work in it, work in it.
