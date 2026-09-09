---
name: decisions
description: >
  Record a decision in the repository's decision log while the work happens,
  and turn the log on or off. Use when a choice that was not quick and easy
  gets settled, when the user asks for one to be written down, or when they
  ask what was decided about a topic and why. Triggers on: record this
  decision, why did we choose, decision log, .claude/decisions, enable
  decisions, disable decisions, what did we decide about. Unlike a document,
  nobody has to ask: where the log is on, a decision that earns a file gets
  one.
---

# decisions: the question, the answer, and what the other options cost

A decision file is the one place the reasoning lives. Answers, commit bodies,
pull request descriptions, READMEs and code comments say what is true now and
point at the file rather than retelling how it got that way.

## The switch

The log is on when `.claude/decisions/` exists in the repository and holds no
`.disabled` file. Everywhere else, write nothing: a repository that never
opted in is not asking for a record, and a `.disabled` marker is somebody who
opted out while keeping what was already written.

Check it before writing. `/decisions:enable` and `/decisions:disable` are how
it moves, and both run `bin/decisions` rather than editing anything by hand.

## What earns a file

A decision that was not quick and easy, plus any the user asks for however
small it looks. A one-off question answered in a sentence does not: a file per
"yes, push it" is churn nobody reopens.

One file per topic, `<unix-timestamp>-<slug>.md`, however many decisions the
topic takes. The timestamp is when the topic opened, so a file keeps its name
for as long as it is argued.

## The file

```markdown
# Which git binary the installer uses

Topic: the installer has to pick a git binary and the choice keeps coming back
Status: decided 2026-09-07
Opened: 2026-09-07

## 2026-09-07

q: Which git should we use: system, brew, user specified
a: use system git, cache the binary location for a day
why: brew git moves with the machine, system git does not
alt: git from $PATH on every call — 700ms of extra runtime
alt: a configured path — one more thing to set per machine
```

`Topic:` is what the topic exists to solve, one line, word for word the same
for as long as it is open. `Status:` reads `open` while any `q:` has no `a:`,
and `decided <ISO date>` once none do. Entries append under the date they were
written, newest last.

`why:` is the reason that was argued, one line. Leave it out when nobody gave
one. `alt:` is one rejected option per line and what killed it: keep the
number, drop the method, so "700ms of extra runtime" rather than which
benchmark said so. An option nobody weighed does not get a line.

Nothing between entries. No paragraph explaining the one above it. Anything
needing more than those four lines belongs in the code or its comment.

## Committing it

The file is committed with the work it belongs to. `**/.claude/` is a common
global exclusion, so run `git check-ignore` before trusting that it landed. If
the log is ignored, say so and stop; `/decisions:enable` prints the carve-out
that fixes the machine. Never reach for `git add -f`.
