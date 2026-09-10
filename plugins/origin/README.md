# origin

A branch, kept on top of the head branch, and the pull request it becomes. One
CLI that a person and an agent run the same way.

```shell
claude plugin install origin@MihaiBojin
codex plugin add origin@MihaiBojin
```

For the terminal, put `bin/` on PATH. The marketplace clone is a stable path
that `claude plugin update` keeps current:

```shell
path+=(~/.claude/plugins/marketplaces/MihaiBojin/plugins/origin/bin)          # zsh
fish_add_path ~/.claude/plugins/marketplaces/MihaiBojin/plugins/origin/bin    # fish
```

From a clone of this repository, point at that `bin/` instead.

## Commands

|                           |                                                          |
| ------------------------- | -------------------------------------------------------- |
| `origin new <name>`       | Fetch, then branch `<name>` off the head branch          |
| `origin sync`             | Fetch, rebase onto the head branch, push with a lease    |
| `origin merge [<number>]` | Merge a pull request with a body written from the change |

Every command takes `--dry-run`, `--yes`, `--quiet`, `--verbose` and
`--no-color`. Commentary goes to stderr and data to stdout, so `--quiet` is
parseable.

## Skills

Type `$` in Codex CLI or `/` in Claude Code, select the skill, and append
arguments or a request. Both clients read the same files under `skills/`.

| Codex CLI       | Claude Code     | Purpose                                           |
| --------------- | --------------- | ------------------------------------------------- |
| `$origin:push`  | `/origin:push`  | Commit the session's work and open a pull request |
| `$origin:sync`  | `/origin:sync`  | Update the branch; `--push` also pushes it        |
| `$origin:merge` | `/origin:merge` | Write the merge body and merge a pull request     |
| `$origin:help`  | `/origin:help`  | Explain the skills and CLI commands               |

For example, `$origin:push --draft` opens a draft pull request in Codex CLI.
The `push` skill runs git and the forge CLI directly.

## Worktrees are not here

`gwa`, `gwr`, `gwl` and `gwm` are shell commands, from
[shell-plugins](https://github.com/MihaiBojin/shell-plugins), and they are
yours to run in a terminal. Both tools read the same two config keys, so they
agree about which remote and which head branch a repository has.

## new

Fetches first, so the branch starts on top of what the remote has rather than
on top of a local copy that may be days old. Nothing has to be rebased
afterwards.

Creates with `--no-track`: a branch off `<remote>/<head>` would otherwise take
the head branch as its upstream, and `git push` would target it.

Refuses a name that is already a branch, naming `git switch <name>` instead,
and a name `git check-ref-format` will not take.

With no name, this branch names the next one: `<branch>-YYYY-MM-DD_NNN`, at the
first number free today, counting both local branches and the remote's. Three
digits, so the sequence cannot be misread as another field of the date. A stem
already carrying that suffix keeps one rather than gaining a second, so a day
of continuations reads as siblings. The head branch names nothing - a branch
off it is a new change rather than the next one - and neither does a detached
HEAD; both ask for a name.

The base is named as `refs/remotes/<remote>/<head>`, never `<remote>/<head>`,
because git resolves a bare name as a tag first and a repository holding a tag
called `origin/main` would branch from the tag.

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
The merge skill can wait for checks when the user asks it to.

## sync

Fetch, then one of four routes, chosen by what the branch is rather than by
what was typed.

On the head branch it fast-forwards, and refuses if that would drop a local
commit. On an unfinished branch it rebases.

On a branch the head branch has only part of, it stops and offers the two ways
on. That branch had its pull request squash-merged and then kept growing, so
the head branch holds its first commits as one commit nothing matches: a rebase
replays those and stops on each. How far the absorption reaches is read by
replaying the branch's tree at each commit as a single commit on the merge base
and asking `git cherry` whether that patch is upstream — the question a squash
merge answers, where a per-commit patch-id does not. The scan runs from the tip
down and takes the highest commit that says yes, because the predicate is not
monotone: the first commit of a squashed pair is not upstream on its own while
the pair is. Past `MERGED_BOUNDARY_LIMIT` commits (50) it is not scanned, and
the rebase runs as it always did.

`--branch <name>` then cherry-picks the commits after the boundary onto a new
branch off the head branch, keeping them as they are; `--squash --branch <name>`
carries the whole difference as one commit. The branch they come from is never
moved. On a branch whose change is already
in the head branch it does neither, because there is no move to make: a squash
merge rewrites the branch into one commit, so git can no longer match the
branch's patches against it and a rebase replays work the head branch already
has, stopping on commit after commit. That branch is finished, and `sync` says
so and stops. The next change starts on a branch of its own, which is
`origin new <name>`, and this one is left exactly where it is.

`--squash --branch <name>` is the way through a rebase that keeps conflicting
on content the head branch already has. It creates that branch off the head
branch and runs
`git merge --squash` from there, so the two sides are compared as trees with
the fork point as the base: what the head branch has already absorbed merges
into itself and is never mentioned, and the stop — if there is one — is the
only one, on a hunk where the two sides genuinely disagree. The old branch is
never moved, so a stop costs nothing.

`git merge --squash` writes no `MERGE_HEAD`, so `git merge --abort` cannot back
one out. The message says `git reset --merge`, which can.

A dirty tree stops `sync` unless it is told what to do with it. `--autostash`
carries it across with git's own stash, and `--commit` commits the tracked
changes first, asking for the message at the terminal; `--message <text>`
supplies one instead, which is the only form that works with `--yes`, because
nothing here invents a commit message. Untracked files are listed and left:
staging one is how a `.env` or a build directory ends up in a commit, and
nothing can tell that from a file somebody meant to add.

A rebase, a merge, a cherry-pick or a revert already in progress is refused by
name, with the command that finishes or abandons it. Each leaves a half-applied
tree that reads as an ordinary dirty one, and `--autostash` on that would stash
a conflict.

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
not the second, and on that shape a plain push is refused the moment `sync`
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

A branch the remote has never seen gets a plain push: nothing to lease
against, and no force. Either refusal ends the same way — somebody else holds
that name, so rename the branch and push again.

## What it refuses

Enforced in `lib/common.sh`, where every mutation passes, rather than in six
commands that each have to remember:

- No `git reset --hard`, and no `git clean` with `--force`.
- No bare `--force` push; pushes are `--force-with-lease --force-if-includes`.
- No force delete of a branch — `-D`, `-d -f`, `-df`, `--delete --force` —
  unless something has proved the branch's change is already in the head
  branch.
- No `git worktree remove --force`, under any circumstance. Nothing here
  removes a worktree, and the guard outlives the command that needed it.
- No resolving a rebase conflict.
- Nothing reads from a terminal under `--yes`, so an agent invocation cannot
  hang on a prompt nobody is there to answer.

Nothing above takes a flag. `--yes` does not reach them.

## What is replaced, said first

Nothing here deletes a branch. What a rebase and a leased push replace is
printed before it happens, under `--quiet` and `--yes` too, because those lines
are the record of where the branch was:

```
This will replace:
  origin/fix-login at a1b2c3d — restore with: git push origin a1b2c3d:refs/heads/fix-login
```

A rebase carries the same, with `git reset --keep <sha>` as the way back. A sha
that cannot be read is a restore command that cannot be printed, and then the
step does not run.

Every branch is named to git as `refs/heads/<branch>` and the head branch as
`refs/remotes/<remote>/<head>`. `git rev-parse feature` prefers a tag called
`feature` over the branch, so in a repository holding both, the bare name would
answer for the branch — with a different commit — everywhere that decides
whether a branch is finished and which sha brings it back.

One thing that spelling does not cover is the abbreviated sha in a restore
line. `a1b2c3d` is a name to git before it is an object, so a branch or tag
actually called `a1b2c3d` answers for it, and pasting it lands on the wrong
commit. Git says so when it happens - `warning: refname 'a1b2c3d' is
ambiguous` - and the way past it is to name the object outright:

```shell
git rev-parse --disambiguate=a1b2c3d     # the whole sha of the object
```

`a1b2c3d^{commit}` does not help. It peels whatever the name resolved to, which
is the ref.

## Configuration

There is none of its own. The two questions a repository can be asked are
asked of git:

```shell
git config checkout.defaultRemote upstream   # which remote this repo belongs to
git remote set-head upstream --auto          # which branch is the default
```

Both are git's own, so every other tool on the repository reads the same
answer, and a single-remote clone answers both without either being set.
`branch.<current>.remote` stands in for the first when nothing more deliberate
does. The `git-worktree` shell commands read the same two.

The forge is read from the remote's host, and for a host that says nothing — a
GitHub Enterprise server, a self-hosted GitLab — from what `gh` and `glab` are
signed in to.

## Requirements

`git` and `bash`. `jq` and either `gh` or `glab` for `merge`; `new` and `sync`
need neither, and work offline apart from the fetch.

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
