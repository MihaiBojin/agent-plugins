# origin

Git worktrees, pull request merges, and keeping a branch on top of the head
branch, from one CLI that a person and an agent run the same way.

```shell
claude plugin install origin@MihaiBojin
codex plugin add origin@MihaiBojin
./install.sh                            # and on PATH, for the terminal
```

## Commands

|                                     | Aliases            |                                                                    |
| ----------------------------------- | ------------------ | ------------------------------------------------------------------ |
| `origin git-worktree add <branch>`  | `gw add`, `gwa`    | Create a worktree, print its path                                  |
| `origin git-worktree remove <what>` | `gw remove`, `gwr` | Remove a finished worktree, delete a merged branch                 |
| `origin git-worktree list`          | `gw list`, `gwl`   | Branch, drift, state, pull request, age                            |
| `origin git-worktree path <branch>` | `gw path`, `gwp`   | Where that branch's worktree is, or exit 1                         |
| `origin merge [<number>]`           |                    | Merge a pull request with a written body                           |
| `origin renew`                      |                    | Put this branch back on top of the head branch                     |
| `origin doctor`                     |                    | Check git, jq, the remote, the head branch, the forge, permissions |

Every command takes `--dry-run`, `--yes`, `--quiet`, `--verbose` and
`--no-color`. `git-worktree list` adds `--json`, and is the only command with
machine-readable output. Commentary goes to stderr and data to stdout, so
`--json` and `--quiet` are parseable and `cd "$(origin gwa foo --quiet)"`
works.

## Layout

```
<PARENT>/.worktrees/<branch>/<repo>
```

PARENT is the directory holding the main checkout, so repositories side by side
share one root with a directory each, and the same branch name across several
of them groups their worktrees together. A slash in a branch name nests:
`fix/login` lands at `.worktrees/fix/login/<repo>`.

The same layout as the [`git-worktree`](https://github.com/MihaiBojin/shell-plugins)
zsh plugin, which reads the same two config keys, so the two tools see one set
of worktrees.

## add

Fetches first so a new branch starts from a current head branch. Checks out an
existing branch instead of failing. Creates new branches with `--no-track`, so
`git push` cannot target the head branch.

Refuses a destination that belongs to somebody else, in the three positions it
can be wrong: the path is another repository's worktree, the path is _inside_
one, or the path is a non-empty directory because another branch nests under
it. None of these is visible in `git worktree list` — that lists this
repository's worktrees, and a squatter belongs to a different one — so the
owner is read from git directly. Without the check, `git worktree add` creates
a worktree inside another repository's checkout, exits 0, and the host repo
sees an untracked directory that its next `git clean -xdff` deletes.

## remove

Removes a worktree **only when its branch is finished**: git says it is merged,
it is squash-merged, or the forge says its pull request is merged or closed.
The squash is the case git cannot see, because it rewrites the commits; it is
detected by replaying the branch's tree as one commit on the merge base and
asking `git cherry` whether that patch is already upstream — a question about
content rather than history, which is what a squash preserves.

The branch is deleted on git's answer only. The forge's is enough to drop the
checkout and no more: a merged pull request says nothing about the commits
sitting on the local branch, and only the content comparison can say that
deleting it loses nothing.

The head branch is never deleted. A worktree can hold it while the main
checkout is on some other branch, and a head branch the remote already has
reaches the merged test finished, like any other branch. Its checkout goes on
that answer; the branch does not.

A worktree with a detached HEAD has no branch to be finished, so what counts
is whether any ref already reaches the commit it sits on. One that does makes
the removal ordinary. None at all makes this checkout the only thing pointing
at that commit, and the removal is refused until `--force`, which prints
`git worktree add --detach <path> <sha>` as the undo.

An unfinished branch keeps its worktree, because that is where the work is. A
stash on the branch, a lock, the main worktree and the one you are standing in
are each refused with the reason.

A worktree holding uncommitted changes is refused outright, and `--force` does
not override that one. The command lists what is uncommitted and stops; the
checkout is the only place that work exists, and the command that discards it
is the user's to type.

When a branch is deleted the output carries the undo:

```
deleted branch fix-login (was a1b2c3d) — squash-merged
  restore: git branch fix-login a1b2c3d
```

`--force` removes the checkout of an unfinished branch, and never deletes a
branch.

## merge

The default squash body on both forges is the commit list — `wip`, `fix lint`,
`address review comments` — which records how the work happened rather than
what it did. `origin merge --gather` emits the title, description, commits,
diffstat and trailers as JSON; the model writes the body from that; the script
shows it and merges. The branch on the remote is left where it is: GitHub's
"automatically delete head branches" and GitLab's "delete source branch"
already decide that, per repository.

`Fixes #123` and `Co-authored-by:` are re-attached afterwards by the script,
because a trailer stops working the moment it is paraphrased.

The strategy defaults to whatever the repository itself prefers, and a strategy
it forbids is refused before the API is called. Run by hand with no body, the
fallback is the description plus the trailers: deterministic, no bullets.

A conflict, a failing check, a check still running, a protection rule or a
mergeability the forge has not worked out yet is refused by name. Only a
failing check has a way past it, `--with-failing-checks`, because only a
failing check is a judgement somebody can make: they have read it and decided
it does not matter. A draft is a question instead — at a terminal it offers to
mark the pull request ready, and then reads it again, because undrafting can
start checks the draft never ran.

The checks are read once, at the moment of the merge; nothing sleeps or polls,
so a pull request whose CI is still running is a "come back in a minute" rather
than a wait. `gh pr merge --auto` is the queue for that, and it is the forge's to run.
The slash command offers to sit and watch instead, when the user asks it to.

## renew

Three routes, chosen by what the branch is rather than by what was typed.

On the head branch it fast-forwards, and refuses if that would drop a local
commit. On an unfinished branch it rebases. On a branch whose change is already
in the head branch it does neither, because there is no move to make: a squash
merge rewrites the branch into one commit, so git can no longer match the
branch's patches against it and a rebase replays work the head branch already
has, stopping on commit after commit. That branch is finished, so `--auto` or
`--branch <name>` starts the next one from the head branch and leaves this one
exactly where it is.

`--auto` names it `<branch>-YYYY-MM-DD_NNN` at the first free number for the
day. Three digits, so the sequence cannot be misread as another field of the
date. Renewing a renewed branch replaces the suffix rather than adding a second
one.

`--squash` is the way through a rebase that keeps conflicting on content the
head branch already has. It creates the new branch off the head branch and runs
`git merge --squash` from there, so the two sides are compared as trees with
the fork point as the base: what the head branch has already absorbed merges
into itself and is never mentioned, and the stop — if there is one — is the
only one, on a hunk where the two sides genuinely disagree. The old branch is
never moved, so a stop costs nothing.

`git merge --squash` writes no `MERGE_HEAD`, so `git merge --abort` cannot back
one out. The message says `git reset --merge`, which can.

`--squash --probe` answers whether the carry would apply cleanly and stops.
`git merge-tree --write-tree` performs the merge in the object database and
writes nothing — no index, no worktree, no ref — so the question is safe to ask
in the middle of a conflicted rebase, which is where it is worth asking. A
rebase that stops offers the carry only when the probe says it would work,
because advice to try a second route that also conflicts costs the resolutions
already made.

`--push` is opt-in, and which push it sends is decided by whether there is
anything to lease against — the remote-tracking ref, not the configured
upstream. A branch created by hand and pushed without `-u` has the first and
not the second, and on that shape a plain push is refused the moment `renew`
rebases it, which is this branch being brought up to date rather than a name
somebody else took.

So a branch the remote already has is pushed with `--force-with-lease
--force-if-includes`, and the sha it replaced is printed beside the command
that puts it back. The second flag is not decoration: the lease alone compares
against the remote-tracking ref, and a `git fetch` updates that ref, so after a
fetch the lease passes and somebody else's commits are overwritten.
`--force-if-includes` additionally requires the ref being replaced to be
reachable from this branch's reflog — that this clone had those commits and
built on them. Together they accept a branch this clone rebased and refuse one
somebody else pushed.

A branch the remote has never seen gets a plain push: nothing to lease against,
and no force, because a generated name is a guess somebody else may have made
first. Either refusal ends the same way — the name is taken, so take the next
number, and the message names it.

## What it refuses

Enforced in `lib/common.sh`, where every mutation passes, rather than in six
commands that each have to remember:

- No `git reset --hard`, and no `git clean` with `--force`.
- No bare `--force` push; pushes are `--force-with-lease --force-if-includes`.
- No force delete of a branch — `-D`, `-d -f`, `-df`, `--delete --force` —
  unless something has proved the branch's change is already in the head
  branch.
- No `git worktree remove --force`, under any circumstance and with no flag
  that grants one.
- No resolving a rebase conflict.
- Nothing reads from a terminal under `--yes`, so an agent invocation cannot
  hang on a prompt nobody is there to answer.

Nothing above takes a flag. `--yes` does not reach them.

## What goes, said first

Every step that deletes something prints it before asking, and prints it under
`--quiet` and `--yes` too, because those lines are the record of what went:

```
This will delete:
  the worktree at ~/.worktrees/fix-login/proj
  1 ignored path(s) in it, which nothing tracks and nothing restores:
    .env
  branch fix-login (a1b2c3d) — restore with: git branch fix-login a1b2c3d
```

Each deletion carries the command that undoes it: a local branch, a branch on a
remote (`git push <remote> <sha>:refs/heads/<branch>`), a rebased branch
(`git reset --keep <sha>`), a leased push. A sha that cannot be read is a
restore command that cannot be printed, and then nothing is deleted; neither is
a branch that has moved off the sha its restore line names.

Every branch is named to git as `refs/heads/<branch>` and the head branch as
`refs/remotes/<remote>/<head>`. `git rev-parse feature` prefers a tag called
`feature` over the branch, so in a repository holding both, the bare name would
answer for the branch — with a different commit — everywhere that decides
whether a branch is finished and which sha brings it back.

One thing that spelling does not cover is the abbreviated sha in a restore
line. `a1b2c3d` is a name to git before it is an object, so a branch or tag
actually called `a1b2c3d` answers for it, and pasting
`git branch fix-login a1b2c3d` in a repository holding one lands on the wrong
commit. The deletion itself is safe either way: it compares whole shas, and a
branch that no longer resolves to the one its restore line names is kept rather
than deleted, so what is at risk is the paste and not the work.

Git says so when it happens - `warning: refname 'a1b2c3d' is ambiguous` - and
the way past it is to name the object outright:

```shell
git rev-parse --disambiguate=a1b2c3d     # the whole sha of the object
git branch fix-login <that sha>
```

`a1b2c3d^{commit}` does not help. It peels whatever the name resolved to, which
is the ref.

The exception is content git never tracked, where no such command exists.
`--yes` answers for everything above and not for that: a worktree holding
ignored files stops, lists them, and names `--delete-ignored`, which is the
only way through and has to be typed.

## Configuration

```shell
git config git-worktree-plugin.remote upstream   # which remote this repo belongs to
git config git-worktree-plugin.headBranch main   # which branch is the default
```

That is all of it. The worktree root is always `<PARENT>/.worktrees`. The forge
is read from the remote's host, and for a host that says nothing — a GitHub
Enterprise server, a self-hosted GitLab — from what `gh` and `glab` are signed
in to.

## Requirements

`git` and `bash`. `jq` and either `gh` or `glab` for `merge`; the worktree and
rebase commands need neither and work offline.

Written for bash 3.2, which is what a mac ships. CI runs the suite on bash 5 on
Linux and bash 3.2 on macOS.

## Development

```shell
npm run lint:shell    # shellcheck, following every sourced file
npm run test:shell    # bats, against throwaway repos and stubbed forge CLIs
```

The tests build a real repository with a real remote — a local bare repository
— plus a sibling repository for the collision cases, and put fake `gh` and
`glab` on PATH that answer from files the test wrote. Nothing reaches the
network.
