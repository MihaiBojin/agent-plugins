---
name: technical-writing
description: >
  Write or review software prose in the shape its reader needs. Use when asked
  to write, draft, edit or review a bug report, postmortem, incident update,
  design doc or RFC, decision record, runbook, error message, PR description,
  commit message, code comment, README or tutorial, status update, review
  comment, deprecation notice, decision request, escalation or handoff, or a
  brief for another agent. Triggers on: write a postmortem, draft an RFC, file
  a bug, write the runbook, word this error message, review this doc. Picks
  the genre, then applies sentence rules adapted from ASD-STE100 and Google's
  technical writing courses.
---

# technical-writing: the reader decides the shape

Every genre here starts from one reader: who they are, the question they
arrive with, and what they do next. The shape follows from those three, and
the sentence rules below apply to all of it.

A repository's own writing rules outrank this skill. Read `AGENTS.md`,
`CLAUDE.md`, `CONTRIBUTING.md` and any style guide first, and follow them
where they disagree with what follows.

## How to use it

1. Find the task in the table below and read that genre file. Do not read the
   other genre files.
2. Set the dials that the genre leaves open. Usually that is only the reader
   distance.
3. Draft in the genre's shape, and apply the shared rules and the document
   rules.
4. Run `self_edit` before you hand the text over.

To review a document, read its genre file and report each finding with the ID
of the rule it breaks.

Source lines name Google's Technical Writing One and Two as TW1 and TW2, and
ASD-STE100 Issue 9 as STE. A rule marked "practice" comes from neither.

## Pick a genre

| Writing task                                     | Genre                                          | Reader's moment                    | Shape                                                   | Length                            |
| ------------------------------------------------ | ---------------------------------------------- | ---------------------------------- | ------------------------------------------------------- | --------------------------------- |
| Changelog entry, release note                    | [Release note](genres/release-note.md)         | Scanning before an upgrade         | One entry per observable change; breaking changes first | One to three sentences per entry  |
| Describe a problem, file a bug                   | [Problem statement](genres/problem.md)         | Triaging or reproducing            | Fixed fields                                            | About half a page                 |
| Explain an outage afterwards                     | [Postmortem](genres/postmortem.md)             | Studying, then funding fixes       | Summary, impact, timeline, causes, actions              | One to four pages                 |
| Communicate during an incident                   | [Incident update](genres/incident-update.md)   | Under pressure                     | Conditions, actions, needs, next update time            | Under 100 words                   |
| Propose or design a component                    | [Design doc](genres/design-doc.md)             | Deciding whether to approve        | Summary, goals, non-goals, proposal, alternatives       | Two to ten pages                  |
| Record a settled choice                          | [Decision record](genres/decision-record.md)   | Asking why it is like this         | Context, decision, consequences                         | Under a page                      |
| Tell someone how to run an operation             | [Runbook](genres/runbook.md)                   | Executing, possibly at night       | Numbered steps with warnings                            | About 20 words per step           |
| Say what failed, to the person it failed for     | [Error message](genres/error-message.md)       | Blocked                            | Cause, fix, example, code                               | One to three sentences            |
| Ask for a review                                 | [PR description](genres/pr-description.md)     | Deciding whether to approve        | What it does, how it was verified, risk                 | One screen                        |
| Record a change in history                       | [Commit message](genres/commit-message.md)     | Reading `git log` or `git blame`   | Subject, then why                                       | Subject under about 72 characters |
| Explain code to its next maintainer              | [Code comment](genres/code-comment.md)         | Changing the code                  | Why, not what                                           | One to three sentences            |
| Introduce a project, teach a task                | [README and tutorial](genres/readme.md)        | Evaluating, installing or learning | What, install, quickstart, usage, limits                | One page plus links               |
| Report progress                                  | [Status update](genres/status-update.md)       | Scanning for risk                  | Changes, risks, needs, next                             | About five lines                  |
| Review a change                                  | [Review comment](genres/review-comment.md)     | Fixing their change                | Severity, finding, evidence, fix                        | One to four sentences             |
| Announce a deprecation or a break                | [Deprecation notice](genres/deprecation.md)    | Checking impact                    | What, who, what to do, by when                          | Under a page                      |
| Ask for a decision                               | [Decision request](genres/decision-request.md) | Choosing                           | Recommendation, reason, trade-off, deadline             | Under 200 words                   |
| Escalate, hand off, stop unsafe work             | [Escalation and handoff](genres/handoff.md)    | Taking ownership                   | SBAR, I-PASS or CUS fields                              | Short                             |
| Brief another agent                              | [Agent brief](genres/agent-brief.md)           | Starting with no context           | Role, goal, context, constraints, output                | What the task needs               |
| Advisory, API or CLI reference, log line, others | [Short forms](genres/short-forms.md)           | Varies                             | One line of guidance each                               | Varies                            |

The lengths are working targets from practice, not rules from the sources.

## The dials

Genres differ along a few settings. Each genre file fixes them, so adjust only
the reader distance unless the genre says otherwise:

| Dial            | Settings                                                                        | Source                                                                               |
| --------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Reader distance | Same team, other team, external developer, end user, executive                  | TW1 Audience: role, then proximity, then the time since they last used the knowledge |
| Reader's moment | Scanning, deciding, executing, debugging, studying                              | The genre                                                                            |
| Mood            | Imperative in steps, indicative in descriptions, never mixed in one list        | STE 4.3, 5.3, Section 6                                                              |
| Tense           | Present for behavior, past for timelines, future only for commitments           | STE 3.2 limits tenses; the split is practice                                         |
| Person          | "You" for the reader, "we" for the organization                                 | TW2; STE 3.6                                                                         |
| Voice           | Active with a named actor; passive only when the actor is unknown               | STE 3.6; TW1 Active voice                                                            |
| Evidence        | None, links, numbers, logs, commits                                             | The genre                                                                            |
| Lifetime        | Ephemeral (chat, status), living (README, runbook), frozen (an archived record) | Practice                                                                             |
| Register        | Neutral: no humor, apology, blame or marketing                                  | Google Writing Helpful Error Messages, Set tone; TW1 Clear sentences                 |

## Shared rules

The dialogue plugin applies these rules to chat replies. Each one has the same
ID and the same first line in both plugins, and a test in the marketplace
repository fails when the two differ. The text under the first line is for
documents only.

### `bluf`

Lead with the answer, result, decision, or blocker.

A reader who stops after the first sentence still has the point. In a
document, that sentence is the answer, the change or the ask. Put the key
points at the start instead of building to them.

Sources: TW1 Documents and Paragraphs.

### `sufficient`

Include only what the reader needs to understand, decide, act, or verify.

Write for a named reader: give what they need for the task, minus what they
already know. State the scope at the start, and say what is out of scope when
a reader could reasonably expect it.

Sources: TW1 Audience and Documents; Tech Writing for Accessibility.

### `direct`

Use active voice, precise nouns, and concrete verbs. Name the actor, or say it is unknown.

Active voice is actor, verb, target: "the scheduler retries the job", not "the
job is retried". When the actor is unknown, say so, and never invent one.
Prefer a strong verb to a noun: "roll back", not "perform a rollback of". Cut
"there is" and "there are".

Sources: STE 3.6, 3.7; TW1 Active voice and Clear sentences.

### `quantify`

Use measurements and thresholds instead of vague qualifiers when relevant.

Give the direction, the number, the unit and the threshold: "cuts p95 from 220
ms to 35 ms", not "much faster". Every number carries its unit.

Sources: STE 4.1; TW1 Clear sentences.

### `epistemic`

Separate verified facts, inferences, unknowns and proposals; name missing evidence instead of filling the gap.

Say which statements are facts, inferences, unknowns or proposals. A timeline
holds facts, and the analysis goes in its own section.

Sources: practice.

### `no_filler`

Remove praise, pleasantries, repetition, and needless adjectives or superlatives.

Keep the tone neutral: no blame, apology, humor or sales language. Cut filler
phrases: "at this point in time" is "now", and "is able to" is "can".

Sources: Google Writing Helpful Error Messages, Set tone; TW1 Clear sentences.

### `terminology`

One name per concept and one sentence pattern per repeated step. Introduce a short form once and then use only it. Quote identifiers exactly.

Two names for one thing read as two things. Quote identifiers, UI text and
error strings exactly as the reader will see them.

Sources: STE 1.11, 8.6, 9.4; TW1 Words; Google Writing Helpful Error Messages.

### `plain_words`

Prefer common words. Avoid idioms, slang, Latin abbreviations, and phrasal verbs that have a one-word equivalent, unless the phrasal verb is the established term (log in, roll back).

Culture-bound references, such as sports, holidays and pop culture, count as
idioms. A reader in a second language, a screen reader and a translation tool
all handle plain words better.

Sources: STE 1.9, 1.10, 9.3, GR-6; TW1 Audience; Tech Writing for
Accessibility, Edit for accessibility.

### `noun_clusters`

Keep noun stacks to three words. Unpack longer ones with of, for or that. Write a long official name in full once, then use a declared short form.

"The cache eviction policy configuration file" becomes "the configuration file
for the cache eviction policy".

Sources: STE 2.1, 2.2.

### `complete_grammar`

Keep articles, subjects, verbs and the conjunction "that", and write no contractions.

A fragment belongs only where the genre allows one: a commit subject, a table
cell, a list of field names.

Sources: STE 4.2, 4.5, GR-1.

### `short_sentences`

One idea per sentence. Aim for 20 words in an instruction and 25 in a description; an identifier, number or quoted string counts as one word.

A long sentence joined by "or" or "and" is often a list that has not been
written yet.

Sources: STE 4.1, 5.1, 6.3; TW1 Short sentences.

### `one_topic`

Start each paragraph with its point, keep one topic, and split after six sentences.

Most paragraphs need three to five sentences.

Sources: STE 6.4 to 6.6; TW1 Paragraphs.

### `scannable`

Introduce a list with a sentence ending in a colon. Number ordered steps, bullet the rest, and keep items parallel and one level deep.

Parallel items share their grammar, logical category, capitalization and
punctuation. Start each numbered step with an imperative verb.

Sources: STE 4.3; TW1 Lists and tables.

### `tables`

Use a table when two or more things are compared.

Give each table a header row and short cells, and introduce it with a
sentence. A table with one column is a list.

Sources: TW1 Lists and tables.

### `current_state`

Describe what the code does now, not its history.

READMEs, docs, comments and PR descriptions say what the system does now, for
a reader who never saw the previous version. Commit messages and changelogs
are the exception, because describing a change is their job.

Sources: practice.

### `define_terms`

Define or link a term the reader may not know; spell out an acronym on first use.

An acronym that appears only once stays spelled out.

Sources: TW1 Words; Tech Writing for Accessibility, Edit for accessibility.

### `pronouns`

Replace a pronoun with its noun when the referent is not the nearest noun, and follow "this" with the noun it means.

Google's threshold is five words: when more than five words separate a
pronoun from its noun, repeat the noun.

Sources: STE GR-3, GR-4; TW1 Words.

### `one_action`

Give one executable action per instruction unless actions must happen simultaneously; put the expected result or limit in the same step.

A runbook step holds one action, with the exact command in a code block.

Sources: STE 5.2.

### `imperatives`

Use direct imperative verbs for instructions and order steps explicitly. Do not put "you must" before a command unless skipping it causes damage.

Steps take the imperative and descriptions take the indicative. Never mix the
two moods in one list.

Sources: STE 4.3, 5.2, 5.3.

### `conditions`

State necessary conditions before an action and identify conditional branches.

Put the condition first: "If replication lag is above 30 s, stop the
migration."

Sources: STE 5.4.

### `notes_not_steps`

Notes carry background only: no steps, limits or risks. Check that the procedure still works with every note deleted.

A risk is never a note. It is a WARNING or a CAUTION.

Sources: STE 5.5.

### `warnings`

Put WARNING or CAUTION before the step it guards, then the protective action or condition and the consequence.

The two levels are:

- WARNING: Irreversible harm is possible, such as data loss, security exposure or an outage; also use it when both levels apply.
- CAUTION: Recoverable harm is possible, such as a failed step that can be retried or rolled back.

Write the level in capitals, and never let color alone carry it.

Sources: STE 7.1 to 7.3.

## Document rules

These rules apply to documents and have no counterpart in the dialogue
plugin.

### `self_edit`

Before you hand a document over, edit it as its reader would read it:

1. Read it as the named reader, not as the person who wrote the code.
2. Read the first sentence alone. If it could open any document, replace it.
3. Delete the last paragraph and read the document again. If nothing was lost,
   leave the paragraph out.
4. Read it aloud. Awkward phrasing and long sentences are audible before they
   are visible.
5. For a published page, also read it zoomed in, with the keyboard only, and
   with a screen reader.

Sources: TW2 Self-editing; Tech Writing for Accessibility, Edit for
accessibility; practice.

### `no_visual_only`

Meaning never depends on sight alone. Color, shape, pattern, font styling and
directional words such as "top-right corner" always come with text: a label, a
word or a legend. In a terminal, a color comes with a word such as FAIL or
WARN. Text and diagram colors meet the WCAG contrast ratios, 4.5:1 for small
text and 3:1 for large text, measured with a checker.

Sources: Tech Writing for Accessibility, Add accessible visuals and Use
sufficient contrast.

### `navigable`

A reader can find their way without seeing the page. Use real headings, one
level-1 title and no skipped levels. Link text names its target, never "click
here" or "learn more". Every image has alt text, and a decorative image has an
empty one (`alt=""`).

Sources: Tech Writing for Accessibility, Edit for accessibility and Write
helpful alt text.

### `inclusive_language`

When a person appears in the text or in an image, give the role that matters,
such as musician or teacher, and give demographics only when they are the
point. Write about disability person-first ("people with disabilities", "uses
a wheelchair") unless the community prefers identity-first terms (Deaf,
neurodivergent). Never call people without disabilities "normal".

Sources: Tech Writing for Accessibility, Choose language that benefits
everyone and Write helpful alt text.

## Sources

The rules adapt four Google for Developers courses, licensed CC BY 4.0:
[Technical Writing One](https://developers.google.com/tech-writing/one),
[Technical Writing Two](https://developers.google.com/tech-writing/two),
[Writing Helpful Error Messages](https://developers.google.com/tech-writing/error-messages)
and
[Tech Writing for Accessibility](https://developers.google.com/tech-writing/accessibility).
STE rule numbers refer to Part 1 of ASD-STE100 Issue 9. The wording here
paraphrases the specification, which may not be reproduced. The
[NOTICE](../../NOTICE) file carries the attribution.
