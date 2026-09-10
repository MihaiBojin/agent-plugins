---
name: ship-it
description: Finish publishing the current change, from uncommitted work or an existing PR/MR through CI fixes and merge. Use when the user asks to ship the change through merge.
---

Finish the steps still needed to publish the user's change. Both clients read
this skill: `$origin:ship-it` in Codex and `/origin:ship-it` in Claude Code.
Arguments are the user's scope and constraints, not a shell variable.

An explicit request to ship through merge authorizes branch creation, carrying
the selected work, commits, pushes, PR/MR creation, CI repair, and merge with
the repository's defaults. It also authorizes choosing a branch name and
writing the PR and merge bodies. Show those choices as you proceed; do not ask
again for routine steps. Loading this skill while discussing it does not
authorize publishing. Honor narrower instructions such as "stop at the PR".

Read the repository's instructions first. Use the existing
[push skill](../push/SKILL.md) for staging and commit conventions and the
[merge skill](../merge/SKILL.md) for the final merge. In this workflow, the
authorization above supplies the push skill's routine confirmations and the
merge skill's `--yes`. The branch and remote rules below govern this run.

Resolve the plugin root from the installed skill location. It is the parent
of `skills/`, two directory levels above the `ship-it` directory. Keep the
working directory in the repository being shipped. `<origin-bin>` below is
the absolute path to that root's `bin/origin`; do not depend on PATH.

## Route the work

Read [model routing](references/models.md) before delegating. Use fast workers
for git inspection, log collection, check polling, and publication mechanics.
Use the most capable available model immediately for code changes and conflict
resolution. A routine failure escalates after three unsuccessful attempts at
the same cause. Keep one writer in the checkout; read-only workers can run
alongside it.

Keep a run record in an OS temporary file: the scoped paths and commits,
starting branch and SHA, both remote identities, target branch, PR/MR URL,
last tested and pushed SHA, and each issue with its attempts, model, solution,
and validation. Carry that record into every worker and resume. Do not commit
the record or include credentials or full CI logs in it.

## Find the next unfinished step

Inspect status, staged and unstaged diffs, untracked paths, branch history, and
any rebase, cherry-pick or merge already in progress. Resolve the destinations
using [remotes](references/remotes.md) before any network mutation. Look up an
existing PR/MR in the target project by source project **and** branch; a number
alone or a matching branch name in another fork is insufficient.

| Observed state                                                            | Continue from                                                      |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Scoped work on the default, shared, detached, or previously merged branch | Create a dedicated branch and carry the work                       |
| Dedicated branch with the intended work                                   | Preserve it and its PR/MR; update from the target base when needed |
| Work committed but not pushed                                             | Validate and push                                                  |
| Open PR/MR with the intended head                                         | Check outstanding changes, then run CI and merge                   |

If the change is already merged and no scoped work remains, report the merge
and stop. A closed, unmerged PR is not success; establish why it was closed
before reopening it. A clean checkout with no change and no open PR needs no
empty commit or PR.

"Dedicated" means its commits belong to this change, it is not the target's
default/shared branch, and its review has not already merged. Do not infer
that from a branch name alone. Preserve an existing stack's parent branches;
ship only the layers in the user's scope, bottom first. An unshipped parent
outside that scope is a dependency to report, not permission to merge it.

If no narrower scope was supplied, inspect the current change as the candidate
scope, including work from before this agent session. Include files that
clearly belong to it. Leave unrelated work out. Ask only when a file or commit
cannot be assigned to the change from the available evidence. Never sweep
untracked files, secrets, or build output into a commit with `git add -A`.

## Prepare the branch without losing work

Fetch the resolved base remote and read its current default-branch ref. For a
new dedicated branch:

```bash
<origin-bin> new <chosen-name> --yes
```

Run this with the base-remote context from the remotes reference. It creates
from the freshly fetched remote head with `--no-track`.

Before switching, record the original HEAD and the intended commit range.
Keep the original branch intact; give a detached HEAD a local recovery branch
before moving it. Preserve dirty work in a named stash, including inspected
untracked paths when necessary, and record its exact OID and staged-path
state. Do not overwrite or pop a pre-existing stash. If unrelated dirty work
must be put aside to switch, record it separately and restore it to its
original checkout before declaring the run complete.

Create the new branch, cherry-pick only the identified unpublished commits in
oldest-first order, then apply the recorded dirty work. Use `stash apply`,
keeping the stash until every intended path and change is verified. Restore
the staged/unstaged split when possible. Never guess a commit range from
`HEAD~N`, reset the source branch, skip a conflicting commit, or drop a stash
whose contents have not been recovered.

For a dedicated branch, preserve its PR/MR identity. Rebase onto the fetched
target base when it is behind, keeping a recovery ref first. For a branch with
already absorbed commits, use Origin's existing `sync --branch <name> --yes`
carry route to move only the remaining commits onto a new branch. Read the
[sync skill](../sync/SKILL.md) for that route. Preserve commits by default;
do not silently choose `--squash`. A stacked branch rebases onto its parent,
not directly onto main.

An operation already in progress is not an invitation to abort another task.
Confirm it belongs to this change before continuing. Route every rebase,
cherry-pick, or stash conflict to the strongest model, with the original
intent, both sides, and relevant tests. Resolve the logic, stage exact paths,
and continue the operation. If intent cannot be recovered, abort only the
operation this run started, preserve the recovery refs/stashes, and report the
specific decision needed. Never choose all of "ours" or "theirs" blindly.

## Validate, commit, push, and open the review

Run the repository's required checks, including release metadata and generated
files. Inspect the diff after formatters. Have the strongest worker fix code
failures, then run the relevant tests and the required checks. Commit by path
with the configured signing and harness trailers intact.

Use the remotes reference for explicit pushes and PR/MR creation. Check each
step's live state before doing it: an interrupted run may already have pushed
or created the review. Reuse the open PR/MR and update its body when the final
change warrants it. Show the title, body, source, and target in the reply.
Publish a non-draft review; an existing draft is marked ready only when this
change is ready for the requested shipping workflow.

## Drive CI to green

Read [CI and retries](references/ci.md). Poll every 30 seconds using the host's
interruptible wait/background facilities, and keep the user informed at least
once a minute. Collect current-head failures with a fast worker; have the
strongest worker diagnose and change code. Validate, commit, push, and repeat
until the current head passes. A successful local test is evidence for the
fix, not a substitute for the new remote run.

## Merge with Origin's defaults

Use the merge skill with the exact PR/MR number and `--yes`, preserving the
explicit target context from the remotes reference. Gather again immediately
before merging. Recheck the source project, source branch, head SHA, target
project, and target branch against the record. A changed head invalidates the
CI result and written merge body; return to inspection and checks.

Write and show the merge body as the merge skill requires, then call its
`<origin-bin> merge <number> --body-file <file> --yes` path. Leave the merge
strategy to the repository. Never supply `--with-failing-checks`, an admin
bypass, or branch deletion flags as an automatic remedy. Pending checks go
back to the wait loop; conflicts go to the strongest worker; required human
reviews or external approvals are blockers to report.

Verify the forge reports **merged**, with its merge SHA and target, before
declaring success. A queued merge is still pending: monitor it and its checks.
For scoped stacks, verify each lower merge, refresh the next layer's target,
and validate its current head again before merging it.

## Report the outcome

Lead with merged, pending, or blocked, and give the PR/MR URL and target. For a
merge, include its SHA and the final release version when there is one.
Summarize every issue encountered: what failed, what happened, the solution
chosen, and the evidence that it worked. Include failed approaches and model
escalations when they explain the solution. If there were no issues, say so.
Name any remaining blocker and the exact branch, stash, or recovery ref that
holds unfinished work. Do not call an unmerged PR shipped.
