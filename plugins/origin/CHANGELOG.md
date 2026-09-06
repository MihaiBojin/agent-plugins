# origin

Newest release first. Each says what changed, and the choices behind it.

## 0.8.0

- `git-worktree path <branch>` prints the path of the worktree that has that
  branch checked out, and exits 1 when no worktree of this repository has it.
  It takes `gw path` and `gwp` as well. A shell function that means to `cd`
  there gets the path alone on stdout and the reason on stderr, so it can tell
  "there it is" from "make one first" without parsing anything.
- `git-worktree add` and `git-worktree remove` answer for every branch rather
  than five in eight. Asking about a branch whose worktree was not among the
  first few records exited 141 with no output at all.

### Choices

`worktree_path_of_branch`, `worktree_branch_at` and `worktree_record_at` read
their records from a here-doc rather than a pipe. Each pipes into an `awk` that
`exit`s on the first match; `exit` closes awk's stdin while `worktree_records`
is still writing, the writer takes SIGPIPE, `pipefail` turns that into 141 and
`set -e` ends the program silently. It only starts once the match sits far
enough down the list, which is why it looked like a repository-size bug rather
than a shape bug. The here-doc is the same form `worktree_records` already uses
to read `git worktree list`, so no new idiom arrives with the fix.

The regression test makes nine worktrees. Every other worktree test makes at
most three and then asks about the one it just made, which is always the last
record, so the whole suite could run green against the crash - and did, through
two releases.

`path` reports only where a worktree _is_, never where one _would_ go. `gwa`
already prints the destination when it makes one, and a single command that
sometimes means "here it is" and sometimes "here is where it would be" cannot
be `cd`-ed to without asking a second question.

No command document under `commands/`. `path` answers a shell function, not an
agent: an agent that wants the checkout runs `gwa`, which makes it when it is
missing and prints the path either way.

## 0.7.1

Git resolves a bare ref name through `refs/<name>`, `refs/tags/<name>`,
`refs/heads/<name>`, `refs/remotes/<name>`, in that order, so a tag wins. This
plugin named branches bare, and in a repository holding a tag and a branch of
the same name it asked git about the tag and acted on the answer.

- `git-worktree remove` no longer deletes unmerged work and prints a restore
  command that does not restore it. It read the tag, called the branch
  finished, deleted it, and printed `git branch <b> <sha>` naming the tag's
  commit, so the work was left in the reflog and the way back did not lead
  there. ([#2](https://github.com/MihaiBojin/agent-plugins/issues/2))
- `renew --auto` names the next branch after the branch, not after
  `heads/<branch>`. `git symbolic-ref --short` returns the shortest spelling
  git can still resolve, which beside a tag of the same name is
  `heads/feature`; the same reading turned the head branch into
  `remotes/origin/main`, which resolves to nothing.
- `git-worktree add` checks out a branch that exists only on the remote when a
  tag matches `<remote>/<branch>`. It died with `fatal: ambiguous object name`.
- `renew --push` pushes. Git refused a bare source refspec matching both a
  branch and a tag with `src refspec matches more than one`.
- A refused leased push names the branch to look at in full. `git log
origin/feature` is what it printed, and that is the moment somebody decides
  whether the work on the remote is theirs to overwrite.
- A branch is deleted only while it still points at the commit its restore line
  names. `git branch -d` deletes a name and takes whatever that name points at
  now, and nothing tied that to the sha printed a moment earlier.

### Choices

A local branch is `refs/heads/<branch>` wherever it reaches git as a revision,
and the head branch is a full ref. `ref_name` puts it back into the form a
person writes, so every message reads as it did before.

The commands this plugin prints keep the full ref. `git merge --ff-only
refs/remotes/origin/main` is what actually runs, and a restore command that did
not do what it said is the whole of #2; a prompt showing something shorter than
the thing it is about to run is the same mistake in a smaller place.

Four spellings stay bare, each for a reason git gives. `git worktree add <path>
<branch>` reads a bare name as a branch to check out and a full ref as a commit
to detach at, and already prefers the branch. `@{upstream}` is branch syntax:
git refuses `refs/heads/<branch>@{upstream}`, and the short form already reads
the branch. `git branch -d` takes a name, not a revision. And `--base <ref>` is
whatever the user typed, where a tag is a legitimate thing to branch from.

The delete guard compares whole shas rather than the abbreviation it prints,
because `a1b2c3d` is a name to git before it is an object and a branch actually
called that would answer for it.

The restore lines still print the abbreviation, and a repository holding a ref
by that name can still read one wrongly. Printing forty characters on every
line that names a commit would cost every reader something to protect against a
ref named like a short sha, which is rarer than the tag this release is about.
The half that loses work is closed instead: nothing is deleted unless the whole
sha still matches, so a line that reads wrongly is a paste that lands somewhere
unexpected rather than work already gone. Git warns on the ambiguity itself,
and README.md gives `git rev-parse --disambiguate=` as the way past it, beside
the restore lines it applies to.

A head branch that is neither a branch here nor a branch on the remote goes
back to git exactly as it came, rather than being prefixed into
`refs/heads/<name>` and resolving to nothing.

`tests/refs.bats` holds what a tag and a branch of the same name do to every
answer this plugin reads. Five more live beside the commands they belong to.
Run against 0.7.0, fifteen of the seventeen fail, along with two existing
assertions; the two that pass there are controls for the sha check, which 0.7.0
does not have.

## 0.7.0

- `git-worktree remove` never deletes the head branch. A linked worktree can
  hold it while the main checkout is on some other branch, and a head branch
  the remote already has reaches the merged test finished, so nothing else
  stopped the deletion.
  ([#3](https://github.com/MihaiBojin/agent-plugins/issues/3))
- A head branch named by `git-worktree-plugin.headBranch` is read as a branch
  name whichever way it is written: `origin/main` and `refs/heads/main` both
  name `main`.
- `git-worktree remove` takes a worktree with a detached HEAD. It goes when
  some ref already reaches the commit it sits on. When none does, the removal
  is refused, and `--force` prints `git worktree add --detach <path> <sha>` as
  the undo.
- `merge` leaves the branch on the remote where it is. `--no-delete-branch` is
  gone along with the behaviour it turned off, and says so.
- `--dry-run` and the run it describes name the same head branch. The
  `ls-remote` that answers when `refs/remotes/<remote>/HEAD` is missing writes
  nothing, so a dry run makes it too.

### Choices

The branch on the remote is the forge's to delete. GitHub's "automatically
delete head branches" and GitLab's "delete source branch" already decide it per
repository, so a `git push --delete` from here duplicated that decision and
re-derived protections the server enforces anyway. Against a branch the server
protects it reported `could not delete <branch>; it may already be gone`, which
was never true.

A worktree holding the head branch is removed rather than refused. Keeping the
head branch in a worktree of its own, with the main checkout elsewhere, is an
ordinary way to work, so the checkout is ordinary to remove; only the branch is
not. MihaiBojin/shell-plugins refuses the whole operation, and the two tools
disagree on purpose.

`repo_head_branch` is not cached. It is read inside `$( )` everywhere, so an
assignment made there dies with the subshell, and resolving it once in
`repo_require` would make every command fail in a repository whose default
branch is unclear — including the commands that never ask. A caller needing
both the branch and the ref asks once and passes the branch to
`repo_head_ref_for`.

A missing `refs/remotes/<remote>/HEAD` costs an `ls-remote`, and that is rare
enough to accept. `git fetch` creates the ref, since
`remote.<name>.followRemoteHEAD` defaults to `create` on git 2.48 and later,
and `repo_fetch` runs first. What is left is an older git, an explicit
`followRemoteHEAD=never`, a remote advertising no HEAD, or a fetch that failed.
