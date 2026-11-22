# technical-writer

Write software prose in the shape its reader needs: bug reports, postmortems,
runbooks, design docs, error messages and the rest.

A postmortem, a runbook and an error message fail in different ways, because
each one has a different reader at a different moment. The skill starts from
that reader: who they are, the question they arrive with, and what they do
next. Sentence rules adapted from ASD-STE100 Simplified Technical English and
Google's technical writing courses apply to all of it.

## What it covers

The skill has one genre file for each of these:

- Release notes, which the release plugin owns when it is installed
- Bug reports and problem statements
- Postmortems and incident updates
- Design docs, RFCs and decision records
- Runbooks and procedures
- Error messages
- PR descriptions, commit messages and code comments
- READMEs, tutorials, how-tos and references
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

A pull request description has its own skill, `pr-description`, and its own
agent. The skill collects the four facts that a diff cannot show: why the
change exists, what was verified, what was not, and what can break. When the
change can be read as a diff, the skill hands those facts to the
`pr-description` agent. The agent reads the diff, writes the title and the
body, checks each claim against the diff, and returns the facts it could not
find instead of guessing them. It runs on the session's model.

The description opens with what the code does after the merge, then gives the
reason, the verification and the risk. `genres/pr-description.md` has the
format and its sources.

## How it fits with the other plugins

- The dialogue plugin applies 22 of the same rules to chat replies. Each
  shared rule has the same ID and the same first line in both plugins, and a
  test in this repository fails when the two differ.
- The release plugin, from the
  [release-tools marketplace](https://github.com/releasetools/agent-plugins),
  owns release notes and changelog entries. Its `release:write` skill writes
  one change's note; `release:prepare` drafts a release's changelog entry.
- The docket plugin handles the lifecycle of design docs and decision records,
  and this skill supplies their body.
- The readme plugin checks a README against the code it describes.

## Credit

The rules adapt Google's
[Technical Writing One](https://developers.google.com/tech-writing/one),
[Technical Writing Two](https://developers.google.com/tech-writing/two),
[Writing Helpful Error Messages](https://developers.google.com/tech-writing/error-messages)
and
[Tech Writing for Accessibility](https://developers.google.com/tech-writing/accessibility),
CC BY 4.0. ASD-STE100 may not be reproduced, so the skill cites its rule
numbers and paraphrases them. [NOTICE](NOTICE) has the full attribution.

## Install

```
/plugin marketplace add MihaiBojin/agent-plugins
/plugin install technical-writer@mihaibojin
```
