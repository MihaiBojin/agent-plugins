---
name: pr
description: Commit this session's work on a branch and open a pull request
argument-hint: "[--draft] [--branch <name>] [--no-branch] [--no-push]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git switch:*), Bash(git add:*), Bash(git commit:*), Bash(git push --set-upstream:*), Bash(git push --force-with-lease --force-if-includes --set-upstream:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh stack:*), Bash(gh extension list), Bash(glab mr create:*), Read, Write, AskUserQuestion
---

Open a pull request for the work in this session. Arguments: `$ARGUMENTS`

Three flags change what it does, and they are the user's to pass:

|               |                                                                                                                       |
| ------------- | --------------------------------------------------------------------------------------------------------------------- |
| `--no-branch` | Commit on the branch you are on, whatever it is. A second pull request from the same branch is a normal thing to want |
| `--no-push`   | Commit and stop. Nothing is pushed and nothing is opened                                                              |
| `--draft`     | Open it as a draft                                                                                                    |

**It is repeatable, and running it again does only what is left.** A run with
`--no-push` commits; a run after it pushes and opens the pull request; a run
after that finds the branch pushed and its pull request open, says so in one
line, and does nothing. Before each step, check whether it has already
happened - `git status --short`, `git rev-parse @{upstream}`,
`gh pr view --json number,state` - rather than assuming this is the first run.

`bin/origin` does not do this one. Every step below is git and the forge CLI
directly, so the refusals in `lib/common.sh` are not standing behind you. Read
what each command says before running the next, and never reach for `--force`
on any of them.

## 1. Read the change

```bash
git status --short
git diff
git diff --cached
```

Say in one line what this change does. Then decide how many pull requests it
is. One is the common answer. Several is right when the work splits into
layers a reviewer can take one at a time, each building on the one before -
the schema before the query that reads it, the helper before its callers.

Anything in the tree that this session did not touch is somebody else's work.
List those paths in your reply and ask before staging one. Never `git add -A`.

Write the split out in your reply before acting on it: the branch name and the
one-line subject of each layer, in order. Let the user change it.

## 2. Where each layer starts

```bash
git rev-parse --abbrev-ref HEAD
git config --get checkout.defaultRemote              # which remote, if it says
git config --get branch.<branch>.remote              # ...otherwise this
git symbolic-ref --short refs/remotes/<remote>/HEAD  # <remote>/<head branch>
```

Those are git's own keys, and they are what `origin` itself reads, so an answer
taken from them is the answer every other command will use. A single-remote
clone answers both without either being set.

`--no-branch` skips this step: you commit where you are.

- **The first layer** branches off the head branch, unless you are already on
  a branch of your own, in which case that is the first layer.
- **Every later layer** branches off the branch before it. That is the whole
  of stacking: a chain of branches, each one's pull request based on its
  parent.
- `git switch --create <name>` carries the uncommitted work with you. Name
  each branch after its own layer in kebab-case, three or four words.
  `--branch <name>` in the arguments names the first one.
- Starting fresh work with nothing uncommitted is `origin new <name>` instead,
  which fetches first so the branch begins on top of what the remote has.

## 3. One layer at a time, start to finish

Take each layer through commit, push and pull request before starting the
next. A half-built stack is worse than a single pull request, and this order
means an interruption leaves finished work behind rather than five branches
and no reviews.

**Commit.** Stage by path, so the commit holds this layer and nothing else:

```bash
git add <paths>
git commit
```

The message says what the change does, not how the session went:

- One line, imperative mood, under 72 characters.
- A body only when the subject cannot carry it. Wrap at 72.
- Nothing about the conversation: no "as requested", no "per feedback".
- Keep the trailers the harness adds. Signing is `commit.gpgsign` and the key
  is git config's business; never name one.

A decision file under `.claude/decisions/` belongs in the commit with the work
it explains.

**Push.** `--no-push` stops here: say which branch holds the commits and that
nothing has been pushed. Otherwise, which push depends on whether the remote has this branch, which is
the remote-tracking ref rather than the configured upstream:

```bash
git show-ref --verify --quiet refs/remotes/<remote>/<branch>
```

```bash
# it does not: nothing to lease against, and no force
git push --set-upstream <remote> refs/heads/<branch>

# it does: this branch was rebased or amended since
git push --force-with-lease --force-if-includes --set-upstream <remote> refs/heads/<branch>
```

The second spelling is the only force in this command, it is spelled exactly
that way, and a bare `--force` is never it. The lease alone compares against
the remote-tracking ref, which a `git fetch` updates, so after a fetch it would
pass over somebody else's commits; `--force-if-includes` additionally requires
what is being replaced to be reachable from this branch's reflog. Together they
accept a branch this clone rebased and refuse one somebody else pushed.

The remote is the one resolved in step 2. A refused first push means the name
is taken by somebody else's branch: rename with `git branch -m <name>` and push
again. A refused leased push means the branch on the remote carries commits
this clone never had. Do not widen the flags. Say what it said, and stop.

**Open it.** If `gh pr view --json number,state` already names an open pull
request for this branch, there is nothing to open: give its URL and stop.
Otherwise write the title and the body **in your reply**, in full, before
anything is created. Command output is shown to you, not to the user. Then
ask, and let them edit either.

The body is for a reviewer who has not read the diff:

- One line stating the change.
- Three to five bullets on what changed and why, not one per file.
- Say what you did not do, when the change leaves something obvious undone.
- No headings, no preamble, 72 columns.
- In a stack, one line naming the branch below it and what it does.

```bash
gh pr create --base <parent> --title <title> --body-file <path>
glab mr create --target-branch <parent> --title <title> --description <path>
```

`<parent>` is the head branch for the first layer and the previous layer's
branch for every one after it. `--draft` in the arguments adds `--draft` to
either.

Report the URL, then go back to step 2 for the next layer.

## 4. Then, if it is there, link the stack

GitHub only, and only once every pull request is open. `gh stack` is an
extension that teaches GitHub the chain, so the pull requests show each other
and a merge at the bottom updates the rest:

```bash
gh extension list | grep -q gh-stack && gh stack link
```

That is the whole of it. Do not install the extension, do not ask the user to,
and do not mention it on GitLab or in a repository where it does not work.
The pull requests are already stacked by their base branches; linking is a
convenience on top, and its absence changes nothing about what was filed.

It is best effort. If it fails, say so in one line and carry on - the pull
requests are open, based correctly, and nothing about them is waiting on this.
A failure here is never a reason to undo, retry differently, or stop the run.

To merge the stack, start at the bottom: `/origin:merge`.
