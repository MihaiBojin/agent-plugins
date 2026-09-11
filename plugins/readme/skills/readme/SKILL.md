---
name: readme
description: >
  Audit a README against the repository it describes, then rewrite it. Use when
  the user asks whether a README is still accurate, asks to shorten,
  restructure or rewrite one, or wants a README where there is none. Triggers
  on: audit the readme, rewrite the readme, is the readme accurate, the readme
  is out of date, shorten the readme, write a readme. The measure is the
  artifact rather than the prose: a claim is checked by running something.
---

# readme: four passes, in this order

A README is a set of claims about a repository. Each was true when it was
written and the code has moved since, so reading the README tells you what
somebody believed, not what is true. The passes below are ordered because each
one needs the last: you cannot judge length before measuring it, cannot decide
what to keep before finding out what is false, and cannot trust a draft you
have not checked the same way you checked the original.

`/readme:audit` stops after pass 2 and reports. `/readme:rewrite` runs all four
and edits the file in place.

The CLI is `bin/readme` under the plugin root, two directories above this file.
Call it by absolute path; it is not on PATH. Everything it does is mechanical,
and everything below that it does not do is judgement.

Read the repository's own instructions first: `AGENTS.md`, `CLAUDE.md`,
`CONTRIBUTING.md`, and any style guide. Where they disagree with the references
here, they win, and say so in the report rather than silently obeying one side.

## 1. Measure

```shell
<plugin-root>/bin/readme all
```

That prints one `stats` line and a finding for every link, badge and inbound
anchor that does not resolve. Then find out what else the repository documents:
a `docs/` directory, a `man/` page, a site in the GitHub `homepage` field, a
wiki. [references/structure.md](references/structure.md) holds what the
sections are, what order they go in, and what comparable projects weigh.

Record the numbers. A rewrite that cannot say what it cut is a rewrite nobody
can review.

## 2. Verify

The highest-yield pass, and the one a reader cannot do.
[references/verify.md](references/verify.md) has the six checks, the sandbox to
run them in, and what each one caught in a real README. Pass 1 settled the last
of them, the links and the badges. The other five: run the CLI's `--help`
against the documented command list, produce a real artifact and diff it
against any documented file format, run the quickstart end to end where the
machine cannot help it, read whatever else parses flags, and check that a
recommendation to reach for another tool is still true.

Each finding gets the evidence beside it. "The README says version 1, a vault
written today says version 2" is a finding. "The vault format looks outdated"
is a guess.

## 3. Rewrite

Only after pass 2. What is false gets deleted or corrected before anything gets
reorganised, because a well-ordered false claim is still false.

Structure comes from [references/structure.md](references/structure.md) and
sentences from [references/writing.md](references/writing.md). Two moves need
care:

Content maintained somewhere else gets a link rather than a copy. A copy is
wrong from the first day the original changes, and nothing fails to tell you.

Before deleting a section, find what points into it. `readme anchors`
finds the links; `grep -rn "README"` finds the prose references it cannot see,
such as a line in `AGENTS.md` saying a thing is "documented in README.md".
Both have to move with the content.

## 4. Self-audit

Everything in passes 1 and 2, against the draft. Every claim written just now
is a claim, including the ones that felt safe. Then read
[references/humanizer.md](references/humanizer.md) and go through the draft for
its patterns. Take the patterns from that file, not its workflow; the passes
here are the workflow.

The tells that survive a careful draft are §1 not-X-but-Y, §2 one-line closers,
§6 forced triads, §8 dashes and §19 bold as decoration.

## The report

Findings in this order, worst first:

1. Wrong. A claim the artifact contradicts. Give the claim and what the
   artifact said.
2. Broken. A link, badge or anchor that does not resolve.
3. Missing. Something the repository has and the README never mentions.
4. Structure. Order, length, and material that belongs in another file.
5. Prose.

An audit ends there. A rewrite shows the same list, makes the edits, then
prints what the self-audit found in the new draft, including nothing.

## No README yet

The passes hold with pass 1 empty. Verify first, against a repository nobody
has described yet, then write. Do not describe a command you have not run.
