---
name: write-pr-description
description: >
  Use when writing, rewriting, checking or fixing the title or the
  description of a pull request or merge request. Triggers on: write the PR
  description, PR body, PR summary, PR title, describe this change for
  review, before `gh pr create` or `glab mr create`, after pushing commits to
  a branch that has an open pull request, and a description that no longer
  matches its diff. Use it for a short description too.
---

# Write a pull request description

Two people read a pull request's title and body: the reviewer who decides
whether to approve, and whoever later finds the merge commit.
[The format](../write-technical-prose/genres/pr-description.md) serves both. Read
it before you write or judge a description.

A repository's own rules outrank the format: `AGENTS.md`, `CLAUDE.md`,
`CONTRIBUTING.md` and its pull request template.

## 1. Collect what the diff cannot show

Four facts come from the work and not from the diff. Collect them first:

| Fact             | What it holds                                                     | When nobody has it |
| ---------------- | ----------------------------------------------------------------- | ------------------ |
| Why              | The problem, its impact in numbers, and the issue to close        | `not stated`       |
| Verification     | Each command that ran in this work, with what it printed          | `none ran`         |
| Not verified     | Each check a reviewer would expect that did not run, and why      | `nothing left out` |
| Risk and rollout | What can break, whom it affects, the flag or the way to roll back | `not stated`       |

Take each fact from the session, the linked issue or the user. Write the
value in the last column when the fact is missing. A plausible reason that
nobody gave is an invention.

## 2. Write it

If you can read the change as a diff, from a pull request number or a branch
and its base, hand the writing to the `pr-description` agent with the brief
below. The session that made the change remembers how the work went. An
agent that starts from the diff describes what the code does.

If you have only notes, write the title and body yourself using this layout.
Replace the placeholders. Copy the labels as printed so the title and body
can be pasted into the pull request.

```text
Title: <imperative title>

<what the code does after the merge>

## Verification

<command and result>
Not verified: <expected check that did not run, and why>
```

Omit the last line when every expected check ran. Add context, risks and
repository-required sections as described in the format. For a reply drafted
from notes, check the raw Markdown before sending: its first seven characters
must be `Title: `. Strip any bold markers, heading prefix, or enclosing code
fence from the title line. Deliver the title and body directly.

The brief has five lines, and each one is filled in:

```text
Pull request: <number, or the branch and its base>
Why: <fact>
Verification: <fact>
Not verified: <fact>
Risk and rollout: <fact>
```

- Claude Code: call the Agent tool with the agent type
  `technical-writer:pr-description` and the brief as its prompt. Set no
  model, so that the agent runs on the session's model.
- Codex: call `spawn_agent` with `fork_turns` set to `none` and no `model`.
  Start the message with "Take the role in `PLUGIN/agents/pr-description.md`,
  where `${CLAUDE_PLUGIN_ROOT}` means `PLUGIN`", with the path of this plugin
  for `PLUGIN`. Then give the brief.

## 3. Use what comes back

The agent returns a title, a body, its checks and its gaps.

1. Take each gap to the user, or leave the line as the agent wrote it. Do not
   fill a gap yourself.
2. Write the body to a file, and create or edit the pull request with
   `--body-file`. The agent reads and never edits a pull request.
3. Tell the user which checks failed and were fixed. If the client reports
   the agent's token count, give that number too.
