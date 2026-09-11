# Resolve the base, push destination, and review target

Read these facts before creating a branch, since a new branch has no tracking
configuration. Keep them in the run record and reapply them to every command.
Shell variables and environment assignments may not persist between tool calls.

Origin's `lib/repo.sh` resolves the **base remote** in this order:
`checkout.defaultRemote`, the current branch's `branch.<name>.remote`, then
the sole configured remote. Multiple remotes without a valid choice are an
ambiguity to report. Never treat the name `origin` as proof of the PR target.

The **push remote** is separate: use `branch.<name>.pushRemote`, then
`remote.pushDefault`, then `branch.<name>.remote`, then the selected base
remote. Preserve this decision when creating a branch with no upstream.
Check each configured value names an existing remote. When reusing a branch,
verify the chosen push project matches the existing PR/MR's source project.
An explicit push destination can intentionally differ from the branch's fetch
tracking remote; that difference alone is not an ambiguity. A conflict with
the verified review source needs an answer before pushing. Do not push to the
base project's default branch. Read `git remote get-url --push <push-remote>` as well as the
fetch URL: `pushurl` and URL rewrites can send a push elsewhere.

Determine the **target project** from the explicit user target, an existing
PR/MR's target, or the selected base remote. Honor a configured forge default
only after verifying it agrees with that target. A fork's parent alone does
not override an explicit project choice. Resolve the target's default branch
from `refs/remotes/<base-remote>/HEAD` or `git ls-remote --symref`; for an
existing review or stack, retain its intended target branch. If a target
override differs from the selected base, find its matching remote and fetch
that base before branching. If no matching base remote exists, report the
missing mapping rather than creating a branch from another project's main.

Resolve the canonical host/project identities through the forge CLI and check
that the source repository permits a PR/MR into the target. Do not substitute
the login name for the fork owner or discard nested GitLab namespaces. Show
the source project/branch and target project/branch before publication.

## Keep Origin and the forge on the same target

Origin's base resolver deliberately ignores `remote.pushDefault`. Its forge
calls rely on the forge CLI's repository context. Supply that context on every
invocation, including the merge skill's gather and merge calls:

```bash
GH_REPO=<host/owner/target> GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=checkout.defaultRemote GIT_CONFIG_VALUE_0=<base-remote> <origin-bin> new-branch <name> --yes
GH_REPO=<host/owner/target> GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=checkout.defaultRemote GIT_CONFIG_VALUE_0=<base-remote> <origin-bin> merge <number> --gather
```

For GitLab use `GITLAB_REPO=<target-project-url>` instead of `GH_REPO`.
These are process-local settings. If `GIT_CONFIG_COUNT` is already in use,
append the override to its existing entries instead of replacing them. Do
not write persistent remote defaults just to make this run work. Pass `--repo`
to direct forge commands; CI belongs to the target review even when the branch
is pushed to a fork. Follow the pipeline's actual project for GitLab job logs.

## Push explicitly

Fetch the push remote's branch, if present, before assessing divergence. Verify
it contains no other person's work absent from the local history. A new or
fast-forward update uses:

```bash
git push --set-upstream <push-remote> refs/heads/<branch>:refs/heads/<branch>
```

Only a branch this run rebased or amended uses the push skill's guarded form:

```bash
git push --force-with-lease --force-if-includes --set-upstream <push-remote> refs/heads/<branch>:refs/heads/<branch>
```

Do not retry a lease rejection with wider force flags. Record the remote SHA
before replacing it. When `pushurl` differs from the fetch URL, verify the
actual push destination with `git ls-remote` too. Do not lease against a ref
fetched from a different repository; use a new branch or report the missing
tracking mapping. A failed push is not proof that the branch name is taken:
distinguish authentication, policy, transport, and divergence errors first.

## Reuse or create the review

Before creation, list open reviews in the target, matching the full source
project and branch. Re-read after a create timeout before retrying. Query
failure is not an empty result. Keep the verified number and URL afterwards.

For GitHub, pass an explicit base project and source owner:

```bash
gh pr create --repo <host/owner/target> --head <source-owner>:<branch> --base <target-branch> --title <title> --body-file <file>
```

When source and target are the same project, `--head <branch>` suffices.
Some installed CLI versions cannot create an organization-owned fork head
with this syntax. Use a documented supported API with explicit head/base
identities or report that limitation; never create the PR in the fork as a
fallback.

For GitLab, select both projects explicitly:

```bash
glab mr create --repo <target-project-url> --head <source-project-url> --source-branch <branch> --target-branch <target-branch> --title <title> --description <body-text> --yes
```

`--description` takes text, not a filename. Read the body file and pass its
contents as one subprocess argument, or use a documented file-input option
if the installed command provides one. Do not use `--fill` or `--push` after
the explicit push above, since they can select another push destination.

Verify the returned source project, head SHA, target project, and target
branch before continuing. Use the same target context when invoking Origin's
merge skill with the resulting review number.
