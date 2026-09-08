---
name: help
description: What the origin plugin does and which command to reach for
---

`origin` wraps the git, GitHub and GitLab operations that are easy to get wrong
and expensive to get wrong. Each lives in a tested shell script with a stable
CLI; these commands gather intent and read the output back.

| Command          | What it does                                                |
| ---------------- | ----------------------------------------------------------- |
| `/origin:gwa`    | Add a worktree for a branch and print its path              |
| `/origin:gwr`    | Remove a finished worktree, deleting its branch when merged |
| `/origin:gwl`    | Every worktree: branch, drift, state, pull request, age     |
| `/origin:gwm`    | Rename this worktree's branch, and move it to match         |
| `/origin:prune`  | Say which worktrees are finished, and why                   |
| `/origin:merge`  | Merge a pull request with a written body                    |
| `/origin:renew`  | Put this branch back on top of the head branch              |
| `/origin:doctor` | Check git, jq, the remote, the forge and its permissions    |

The same commands run by hand:

```bash
origin --help
```

`git-worktree add` also answers to `gw add` and `gwa`; likewise `remove`/`gwr`,
`list`/`gwl`, `path`/`gwp` and `move`/`gwm`.

## Layout

Worktrees live at `<PARENT>/.worktrees/<branch>/<repo>`, where PARENT holds the
main checkout. Repositories side by side share the root, one directory each, so
the same branch name across several of them groups their worktrees together. A
slash in a branch name nests.

## What it will not do

- No `git reset --hard`, no `git clean --force`, no bare `--force` push. These
  are absolute: no flag reaches them and `--yes` is not a way in.
- No removing a worktree that holds uncommitted work, or a branch with a stash
  on it. There is no flag for this one: the checkout is the only copy, so the
  command says what is uncommitted and leaves it where it is.
- No removing a worktree whose branch is unfinished. `--force` overrides that
  one and still never deletes a branch.
- No deleting a branch, here or on a remote, without printing the command that
  restores it. Where the sha cannot be read, the branch stays.
- No deleting anything git never tracked without being asked in as many words.
  `--yes` answers for what can be restored; ignored files are not that, so
  `gwr` stops and names them even under `--yes`.
- No resolving a rebase conflict for you.

Anything about to be deleted is printed first — the path, the files, the
branch, the sha, the restore command — whatever `--quiet` and `--yes` say.

## Configuration

```bash
git config checkout.defaultRemote upstream   # which remote this repo belongs to
git remote set-head upstream --auto          # which branch is the default
```

Both are shared with the `git-worktree` zsh plugin, so the two tools agree.
