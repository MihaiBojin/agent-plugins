# technical-writer

Write software documentation and pull request descriptions, or check a project
README by running the steps it describes. Install `technical-writer@mihaibojin`
to use all four skills.

| Skill                                                          | When to use it                                                                              |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| [write-technical-prose](skills/write-technical-prose/SKILL.md) | Draft or review a runbook, design doc, postmortem or another kind of software prose.        |
| [write-pr-description](skills/write-pr-description/SKILL.md)   | Write or revise a pull request title and body using the diff and the author's verification. |
| [write-project-readme](skills/write-project-readme/SKILL.md)   | Create or rewrite a README. Verify what the project does and check the finished draft.      |
| [audit-project-readme](skills/audit-project-readme/SKILL.md)   | Report which claims disagree with the project, with evidence for each finding.              |

## What it covers

The prose skill selects a format for the reader and the task. It covers these kinds of writing:

- Release notes, worded for the release plugin, which decides what goes in them
- Bug reports and problem statements
- Postmortems and incident updates
- Design docs, RFCs and decision records
- Runbooks and procedures
- Error messages
- Commit messages and code comments
- Tutorials, how-tos and references
- Status updates, review comments and decision requests
- Deprecation and breaking-change notices
- Escalations and handoffs, in SBAR, I-PASS or CUS form
- Briefs for another agent
- Short forms: security advisories, API and CLI reference, log messages, FAQs,
  meeting notes, interview questions and alt text

The agent loads the skill when asked to write or review one of these, and
reads only the genre file it needs. Every rule has an ID, such as `direct` or
`no_visual_only`, so that a review can cite the rule a sentence breaks.

A repository's own writing rules outrank the skill: it reads `AGENTS.md`,
`CLAUDE.md`, `CONTRIBUTING.md` and any style guide first.

## Pull request descriptions

A pull request description has its own skill, `write-pr-description`, and its own
agent. The skill collects the four facts that a diff cannot show: why the
change exists, what was verified, what was not, and what can break. When the
change can be read as a diff, the skill hands those facts to the
`pr-description` agent. The agent reads the diff, writes the title and the
body, checks each claim against the diff, and returns the facts it could not
find instead of guessing them. It runs on the session's model.

The description opens with what the code does after the merge, then gives the
reason, the verification and the risk. The [PR description format](skills/write-technical-prose/genres/pr-description.md) gives the full structure and its sources.

## Project READMEs

Both README skills accept a path and default to `README.md` in the current
directory. The audit compares the README with the CLI, generated files,
quickstart results, links and workflow badges. It reports wrong claims,
broken references, omissions, structural issues and prose findings in that
order. The writer uses the same checks before editing an existing README
and on the final draft. For a new README it starts from the repository.

The [checker](bin/readme) measures the file and checks links, badges and
inbound anchors with `bin/readme all [file]`. Use
`bin/readme commands <cli> [file]` to compare documented commands with
the command list in the CLI's help. Findings and their total go to stdout.
The individual checks print progress counts to stderr. A successful check
can report findings.

## How it fits with the other plugins

- The dialogue plugin applies some of the same rules to chat replies. Each
  shared rule has the same ID and the same first line in both plugins, and a
  test in this repository fails when the two differ.
- The release plugin, from the
  [release-tools marketplace](https://github.com/releasetools/agent-plugins),
  owns release notes and changelog entries. Its `release:write` skill writes
  one change's note; `release:prepare` drafts a release's changelog entry.
  Both load `write-technical-prose` to word the entries they draft.
- The docket plugin handles the lifecycle of design docs and decision records,
  and this skill supplies their body.

## Credit

The rules adapt Google's
[Technical Writing One](https://developers.google.com/tech-writing/one),
[Technical Writing Two](https://developers.google.com/tech-writing/two),
[Writing Helpful Error Messages](https://developers.google.com/tech-writing/error-messages)
and
[Tech Writing for Accessibility](https://developers.google.com/tech-writing/accessibility),
CC BY 4.0. ASD-STE100 may not be reproduced, so the skill cites its rule
numbers and paraphrases them. [NOTICE](NOTICE) has the full attribution.

The README writer includes the prose patterns from
[blader/humanizer](https://github.com/blader/humanizer) 3.0.0, MIT, © 2025
Siqi Chen. See the [license](skills/write-project-readme/references/humanizer-LICENSE)
and [source revision](skills/write-project-readme/references/humanizer-VENDOR.json).
The patterns draw on Wikipedia's
[Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing),
maintained by WikiProject AI Cleanup under CC BY-SA 4.0.

## Install

```
/plugin marketplace add MihaiBojin/agent-plugins
/plugin install technical-writer@mihaibojin
```
