---
name: help
description: Explain Origin's skills and CLI commands when the user asks for help or usage.
---

Origin provides native skills for pull requests and branch maintenance.
Use `$` in Codex CLI and `/` in Claude Code. Append arguments or a request
after the skill name.

| Codex CLI       | Claude Code     | What it does                                                        |
| --------------- | --------------- | ------------------------------------------------------------------- |
| `$origin:pr`    | `/origin:pr`    | Commit this session's work on a branch and open a PR                |
| `$origin:sync`  | `/origin:sync`  | Fetch and rebase onto the head branch; `--push` pushes with a lease |
| `$origin:merge` | `/origin:merge` | Merge a pull request with a body written from the change            |
| `$origin:help`  | `/origin:help`  | Explain Origin's skills and CLI commands                            |

For example, `$origin:pr --draft` opens a draft pull request in Codex CLI.

The CLI also creates branches:

```bash
origin new [<name>]     # fetch, then branch off the head branch
                        # no name: <branch>-YYYY-MM-DD_NNN, free number today
origin --help
```

`pr` is the one command that does not run `bin/origin` for the steps that touch
the repository: git has no `origin` subcommand for committing or opening a pull
request, so the refusals in `lib/common.sh` do not cover it. A change with
layers in it becomes a stack of pull requests, each based on the branch below,
filed one at a time and finished before the next one starts.

## Worktrees are not here

`gwa`, `gwr`, `gwl` and `gwm` are shell commands, from
[shell-plugins](https://github.com/MihaiBojin/shell-plugins). They are yours to
run in a terminal, and `origin` neither wraps them nor replaces them. Both read
the same two config keys, so they agree about which remote and which head
branch a repository has.

## What it will not do

- No `git reset --hard`, no `git clean --force`, no bare `--force` push. These
  are absolute: no flag reaches them and `--yes` is not a way in.
- No force delete of a branch that nothing has proved merged.
- No resolving a rebase conflict for you.
- No naming a carry for you: `sync --squash` takes the name you give. `new`
  generates one only when you ask for none, and only from the branch you are
  standing on.

Anything about to be deleted or replaced is printed first — the branch, the
sha, the command that puts it back — whatever `--quiet` and `--yes` say.

## Configuration

```bash
git config checkout.defaultRemote upstream   # which remote this repo belongs to
git remote set-head upstream --auto          # which branch is the default
```

Both are git's own, so the `git-worktree` shell commands read the same answer
and a single-remote clone needs neither.
