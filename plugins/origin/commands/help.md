---
name: help
description: What the origin plugin does and which command to reach for
---

`origin` wraps the git, GitHub and GitLab operations that are easy to get wrong
and expensive to get wrong. Each lives in a tested shell script with a stable
CLI; these commands gather intent and read the output back.

Three commands, because those are the three where an agent has something to
add: `pr` reads a session's work and writes the commits, `sync` routes a
conflict, and `merge` writes the body that lands.

| Command         | What it does                                             |
| --------------- | -------------------------------------------------------- |
| `/origin:pr`    | Commit this session's work on a branch and open a PR     |
| `/origin:sync`  | Fetch, rebase onto the head branch, push with a lease    |
| `/origin:merge` | Merge a pull request with a body written from the change |
| `/origin:help`  | This                                                     |

The CLI has one more, and no slash command for it, because there is nothing to
decide once the name is chosen:

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

Both are shared with the `git-worktree` shell commands, so the two tools agree.
