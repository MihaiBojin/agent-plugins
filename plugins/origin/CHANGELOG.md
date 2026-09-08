# origin

Newest release first. Each says what changed, and the choices behind it.

## 0.10.1

- `gwa <branch>` refuses a destination another of this repository's worktrees
  already holds, and names the branch there. It reported success and printed
  the path, so `cd "$(origin gwa <branch> --quiet)"` landed in a checkout on
  somebody else's branch and the requested one never got a worktree. A
  directory whose name no longer matches the branch inside it was enough to
  reach it.

### Choices

The refusal reads the branch out of `git worktree list --porcelain` rather than
out of the path, which is the same source every other command uses. The path
segment is a label; the porcelain is the fact.

## 0.10.0

- `origin prune` says which worktrees are finished, and why, one verdict each.
  It fetches first, clears git's bookkeeping for worktrees somebody deleted by
  hand, and removes nothing without `--yes`. `--branch` narrows it to one,
  `--no-fetch` assesses from what is already here and says the answer may be
  stale.
- `git-worktree move <new>` renames the branch checked out here and moves the
  checkout to match. `gw move` and `gwm` too.
- `install.sh --uninstall` no longer deletes a symlink belonging to a different
  checkout. It removed any symlink named `origin` at the prefix, wherever it
  pointed, and reported `Removed`. Two clones of this plugin and an
  `--uninstall` run from the wrong one was enough to make the other one
  disappear under a success message.
- `install.sh --help` prints the whole header rather than lines 3 to 12 of
  itself.

### Choices

Three verdicts, not two. `unknown` is not `keep` with a softer word: "this is
not merged" and "no upstream says whether any of this was pushed" are different
facts, and a sweep that prints them the same way invites somebody to act on the
wrong one. A branch with no upstream is the common case, and `prune` says so
rather than counting its commits against nothing and calling the answer zero.

`prune` removes by calling `git-worktree remove`, one worktree at a time,
rather than reimplementing the removal. Every refusal that command makes
therefore still applies, and `prune` cannot talk its way past one; each call is
a subshell, because those refusals are `die` and one worktree it will not take
is not a reason to abandon the sweep. The test that matters hands every `go`
verdict to `gwr` and requires it to be taken: `prune` proposing something that
would then be refused is a bug in `prune`.

There is no `--dry-run`. Without `--yes` this only reports, so a flag meaning
"do not act" would be a no-op wearing the clothes of a safety feature, and
somebody would one day read it as the reason a sweep was safe. Passing it is an
error that says as much rather than being quietly accepted.

`git_guard` now skips git's global options before reading the subcommand. It
read `$1` as the subcommand, so `git -C <path> branch -D <branch>` reached it
as a subcommand named `-C`, matched nothing, and went through - and so did
`reset --hard`, `clean -fdx`, a bare `--force` push, and `worktree remove
--force`. Nothing passed a global before now, which is why it had never fired;
`gwm` is the first command that needs `git -C`, and writing it would have
opened the hole rather than found it. A global the guard does not recognise is
refused rather than skipped, because the alternative is reading the token after
it as a subcommand, which is how a guard stops guarding.

`gwm` renames the branch before moving the checkout. `git worktree move`
records the path it moved to, so renaming afterwards would leave the two halves
recoverable in the wrong order if the move failed. Both failure paths say which
half happened and print the command that finishes it.

The new path goes to stdout. A subprocess cannot `cd` its parent, so the shell
that called `gwm` is still standing in a directory that no longer exists, and
the path is what a shell function moves to.

## 0.9.0

`merge --force` is gone. It covered seven unrelated refusals with one word, so
a merge meant to get past a flaky check also got past a blocked review, a
conflict and a draft.

- `--with-failing-checks` replaces it, and covers only failing checks. A
  failing check is a judgement somebody can make, having read it. Nothing gets
  past a conflict, a protection rule, a dirty merge, or a check that has not
  finished.
- `--force` exits 1 and names what took its place.
- A merge needs `mergeable` to say `MERGEABLE`. It tested only the
  `CONFLICTING` arm, and a field the forge had not computed - which arrives as
  `UNKNOWN`, and which a missing field also becomes - fell straight through to
  the merge.
- A draft is a question rather than a refusal. At a terminal it names the
  pull request and offers to mark it ready; with no terminal it refuses and
  prints the command. No flag proceeds past a draft.

### Choices

Both forges compute mergeability asynchronously, so a pull request read moments
after a push answers `UNKNOWN` and answers properly a moment later. A flat
refusal on the first `UNKNOWN` would reject mergeable work at random, which
reads as flaky rather than careful, so it is asked again: three tries, two
seconds apart, and a message that says `could not determine whether it merges
cleanly` rather than `it does not merge cleanly`. **Both numbers are a guess.**
Nothing here has been measured against a live pull request, and that is the
thing to do before trusting them; `ORIGIN_MERGEABLE_TRIES` and
`ORIGIN_MERGEABLE_WAIT` exist so the tests do not sleep, and so the numbers can
be moved without a release.

`--yes` does not answer the draft question. Marking a draft ready changes the
pull request - starting required checks, requesting reviews - rather than
performing one of the ordinary steps `--yes` is there to skip. Everything is
read again afterwards, so a pull request refused only for being a draft can
come back refused for a check the draft never ran. That is the right answer
rather than a bug, and the command document says so.

Refusals carry a kind now: `checks`, `draft`, or `hard`. The flag reads the
kind rather than the wording, so a reason reworded later cannot quietly become
overridable, and a reason added later is `hard` unless somebody decides
otherwise. `--gather` still reports the prose alone, because its consumer is a
model writing a body rather than a flag.

## 0.8.1

- `doctor` fails on a `git-worktree-plugin.headBranch` naming no ref, and says
  which name. It reported `ok` and `ready`, while every reap refused with
  `<branch> is not merged into <name>` for as long as the setting stood.
- A reap refused under that setting names the key rather than only the branch.
  `feature is not merged into does-not-exist` is true and useless: it reads as
  a fact about the branch, and the operator has no way to tell a misconfigured
  key from a branch that exists somewhere they cannot see.
- `git-worktree list` runs 35 git subprocesses over nine worktrees rather than
  63, and takes about half as long. `%cI` and `%cr` come from one `git log` per
  commit rather than two per worktree, and the head ref is checked once for the
  whole list instead of once per row.

### Choices

`repo_head_branch` still returns a stated head branch as written. Making it
refuse an unresolvable name would stop `gwl` and `gwa` too, in a repository
where the only thing wrong is one config line, and `repo_head_ref_for` already
documents passing an unrecognised name through for git to resolve as it always
did. The new message is on the refusal path in `git-worktree remove` alone,
where the cost of the mistake is a destructive command that cannot explain
itself, and it fires only when the name came from the config key and resolves
to nothing. `doctor` holds the full answer and the message points there.

Two caches, both keyed on something that cannot change inside one run: the
commit date pair, keyed by sha, and the main worktree, which `git worktree add`
and `git worktree remove` never move. Neither is read through `$(…)` in the
form that would matter - a subshell takes the cache with it when it exits, so
`worktree_commit_age` sets globals rather than printing, and `worktree_require`
warms the main worktree in the caller's own shell the way `repo_require`
already warms the remote. Nothing caches `worktree_records`: `gwa` and `gwr`
change what it answers.

The main worktree is warmed in `worktree_require` rather than `repo_require`.
Every command calls `repo_require`, and `merge` and `renew` would have paid for
a `git worktree list` neither of them reads.

The head ref's existence is hoisted out of the row loop rather than cached. It
is one fact for the whole list, and a variable says so more plainly than a
lookup would.

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
