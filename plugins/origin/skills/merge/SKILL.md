---
name: merge
description: Merge a pull request, writing the body from the change rather than the commit list
argument-hint: "[pr-number] [--yes] [--with-failing-checks]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *), Bash(git log:*), Bash(git diff:*), Bash(git status:*), Read, Write
---

In Codex, `$ARGUMENTS` means the arguments supplied with the skill. Substitute
them before running a command; do not read them from a shell variable.
Resolve `${CLAUDE_PLUGIN_ROOT}` to the plugin root, two directories above this
`SKILL.md`, if the client has not expanded it. Run the resulting absolute
script path from the repository being worked on.

Merge a pull request. Arguments: `$ARGUMENTS`

The script does everything that touches the repository. Your job is the body.

## 1. Gather

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin merge $ARGUMENTS --gather
```

No number gathers the pull request for the current branch. The output is JSON:
`pr`, `commits`, `diffstat`, `trailers`, `refusals`, `stacked`, `fallback`.

If it fails, report what it said and stop.

`stacked` is true when GitHub has this pull request in a stack, including the
bottom one. GitHub merges those in the background, so the script sends the
merge and then waits for GitHub to say it landed, which takes a few seconds
rather than none. Say so before you write the body; nothing else about the
steps below changes.

## 2. Stop if it is not ready

If `refusals` is non-empty, print each reason and stop. Only one of them has a
way through:

| reason                                        | what to do                                                                                                       |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| these checks are failing                      | stop, unless the user asked for `--with-failing-checks`; then say which you are merging past and carry on        |
| it is a draft                                 | the script asks at a terminal and marks it ready. With none it stops and names the command; report that and stop |
| these checks have not finished                | say which is running, carry on to the body, and offer **Merge on green** at step 4                               |
| its checks are still running                  | the same, without a name to give                                                                                 |
| could not determine whether it merges cleanly | stop. The forge had not worked it out; running again in a minute is the answer                                   |
| it conflicts with the base                    | stop                                                                                                             |
| blocked, a review or a branch protection rule | stop                                                                                                             |
| the forge reports the merge dirty             | stop                                                                                                             |

A draft that is marked ready is read again, so it can come back refused for a
check the draft never ran. That is the right answer, not a failure.

## 3. Write the body

From `pr.title`, `pr.body`, `commits` and `diffstat`, write the body of the
commit that will land on `pr.baseRef`. Its reader is somebody a year from now
with no access to the pull request.

- Lead with one line stating the change, imperative mood.
- Then at most three to five bullets on **what changed and why** — not one per
  commit.
- Drop mechanical commits: `fixup!`, `wip`, `address review comments`, `lint`,
  formatting, merges from the base branch.
- Never invent a rationale. If it is not in `pr.body` or visible in the diff,
  leave it out.
- Wrap at 72 columns. No headings, no `This PR…`, no restating the title.
- Do not write the trailers yourself. The script re-attaches every
  `Fixes #123` and `Co-authored-by:` afterwards, so a body carrying them gets
  them twice.

A small change deserves a short body. One line and no bullets is right for a
one-line change.

Write it to a file with the Write tool. Do not pass a multi-line body as a
shell argument.

## 4. Show it and ask

Write the title and the body out **in your reply** — the message the user
reads — in full, exactly as they will land.

Not a `cat`, not an `echo`, and not a reference back to what the script
printed. Command output is shown to you, not to them, so a body they never saw
is a commit message nobody approved. Never write "as above" or "as printed
above": from where the user is sitting there is nothing above.

**With `--yes` in the arguments**, write them out just the same — they are the
record — and go straight to the merge without asking.

Otherwise, having written them out, ask the user to choose:

- **Edit title** — take their instruction, rewrite the title, show it again
- **Edit body** — take their instruction, rewrite the body, show it again
- **Merge** — go
- **Merge on green** — only when a check that has not finished is the one
  thing standing in the way. Wait for it, then merge

Loop until they pick one of the two merges. The script's own prompt cannot help
here: an agent session has no terminal, so `origin merge` without `--yes` would
refuse rather than ask.

## 4a. Merge on green

The waiting is yours, not the script's. Re-run the gather every 30 seconds, in
the background, and read `refusals` each time:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin merge $ARGUMENTS --gather
```

- Empty — merge, with the body they already approved. Do not ask again.
- Still only the unfinished check — keep waiting. Say nothing each round.
- A failing check, or anything else — stop and say which. A failure is not
  something to wait through, and `--with-failing-checks` is not a flag you can
  assume: it says somebody read the failure and decided it does not matter.

Give up after thirty minutes and report where the checks stood. Never poll
unless the user picked this; the default is to say what is running and stop.

## 5. Merge

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin merge $ARGUMENTS --body-file <the file> --yes
```

The strategy defaults to whatever the repository itself prefers; pass
`--squash`, `--merge` or `--rebase` only if the user asked for one. The branch
on the remote is untouched; whether it goes is the forge's own setting.

A stacked merge that GitHub does not finish is reported rather than retried.
Read the pull request before running this again: it may have landed after the
script stopped waiting.

A merge GitHub hands to a merge queue is reported as queued. Nothing has landed
on the base branch yet, so report it as queued and do not say it merged.

Report the merge and the URL. Do not offer to revert it.
