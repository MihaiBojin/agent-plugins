---
name: help
description: Explain Origin's skills and CLI commands when the user asks for help or usage.
---

Origin provides native skills for pull requests and branch maintenance.
Use `$` in Codex CLI and `/` in Claude Code. Append arguments or a request
after the skill name.

| Codex CLI         | Claude Code       | What it does                                                        |
| ----------------- | ----------------- | ------------------------------------------------------------------- |
| `$origin:ship-it` | `/origin:ship-it` | Finish the change through CI fixes and merge                        |
| `$origin:push`    | `/origin:push`    | Commit this session's work on a branch and open a PR                |
| `$origin:sync`    | `/origin:sync`    | Fetch and rebase onto the head branch; `--push` pushes with a lease |
| `$origin:merge`   | `/origin:merge`   | Merge a pull request with a body written from the change            |
| `$origin:help`    | `/origin:help`    | Explain Origin's skills and CLI commands                            |

For example, `$origin:push --draft` opens a draft pull request in Codex CLI.

The CLI also creates branches:

```bash
origin new-branch [<name>]  # fetch, then branch off the head branch
origin rotate               # the name the next branch would take
                        # no name: <branch>-YYYY-MM-DD_NNN, free number today
origin ci [<number>]   # current PR/MR identity and checks as JSON
origin --help
```

`ship-it` carries the current change through publication and merge, reusing
an existing branch or review when appropriate. It uses fast workers for
routine operations and the strongest available model for code and conflicts.
`origin ci` reads the forge for each poll and reports stale or missing results.
Routine failures escalate after three attempted remedies. The final report
explains the issues and chosen solutions.

`push` and `ship-it` run git and forge commands directly for publication;
`bin/origin` supplies branch creation, synchronization, and merge. A change with
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
- The CLI stops on conflicts. The `ship-it` skill assigns their resolution to
  the strongest available model and validates the result.
- No naming a carry for you: `sync --squash` takes the name you give. `new`
  generates one only when you ask for none, and only from the branch you are
  standing on.

The CLI prints the branch, SHA, and recovery command before replacing
history, whatever `--quiet` and `--yes` say.

## Configuration

```bash
git config checkout.defaultRemote upstream   # which remote this repo belongs to
git remote set-head upstream --auto          # which branch is the default
git config remote.pushDefault origin        # where ship-it pushes the branch
```

`ship-it` keeps the base and push remotes separate when publishing from a fork.
These are git's own settings; a single-remote clone needs no remote override.
