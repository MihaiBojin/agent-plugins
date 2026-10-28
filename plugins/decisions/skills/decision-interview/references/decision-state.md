# Minimal persisted decision state

Use existing formats first. Do not introduce a database, mandatory script or duplicate JSON ledger just to conduct the interview. One saved queue is the source of presentation order and counts; a decision record holds history. A small task may use two sections of one document.

## Open-question record

Store stable ID, short question/topic, status (`open` or `deferred`), dependency/context link and presentation order. Keep the highest allocated ID even when rows are removed; it is the displayed total unless the user explicitly requests a new numbering scheme. The next question is the first eligible open entry, not necessarily the lowest ID. An unresolved deferred row still counts as remaining.

If all open questions are answered but deferred rows remain, say `Active interview complete; 1 deferred question remains.` Do not automatically resume a question the user asked to leave for later, or describe the full design as having no unresolved dependency.

For reductions, retain a disposition table outside the open queue: `answered`, `inferred from accepted decision`, `applied default`, `merged into ID`, `not applicable`, `outside initial scope`, or `delegated implementation work`. Do not use one generic “answered” state for all removals.

## Decision record

Use the existing decisions skill format for `.decisions/`; keep consequences and current behavior in the linked design, without duplicating the reasoning. The following applies when a requested planning package has no established record format. A concise entry normally needs:

- Stable decision ID/date and originating question, if applicable.
- The user's answer in context, or an explicit label for an applied engineering default.
- Accepted behavior and concrete consequences for the design.
- What this supersedes and what remains undecided.
- Relevant design file(s).

Avoid repeating every previously accepted constraint in every entry. Keep the current design readable independently of the chronological ledger. Historical entries may retain earlier choices, but mark supersession clearly when necessary.

## Behavioral examples

**Numeric answer:** question 4 offers local login versus external identity provider. The user says `1`. Save included local login, update setup/authentication sections, remove question 4, then compute the next question from the queue. Do not infer a particular password algorithm or private-key unlock policy.

**Clarification:** while question 6 asks about encryption-key custody, the user asks how an agent works. Explain it and record useful research. Question 6 remains open; neither the tool nor custody model is selected by asking about it.

**Skip:** the user says `Next question`. Move the current item to deferred, without reducing the unresolved count. Present the next eligible open item and explain the deferral briefly.

**Conditional closure:** question 8 asks whether offline access is included; the user excludes it. Remove question 8 as answered and its dependent offline-cache question as not applicable. The remaining count drops by two; explain the skipped ID once.

**Simplification:** the user asks to reduce complexity. Choose defensible small initial defaults where judgment is delegated, move benchmark parameters to implementation work, and retain a question whose answer changes who can access protected data. Log defaults as defaults, not user quotes.

**Review gate:** the user asks to commit the design and review it before coding. Commit the authorized planning state and report the actual commit; do not start a prototype, install dependencies or treat a prepared implementation branch as permission to continue.

## Consistency check before the next question or handoff

Read the actual queue and verify: IDs are unique, resolved rows are absent, every removal has a disposition, deferred dependencies are visible, the shown count matches unresolved rows, and the next displayed ID matches the next eligible row. Check links affected by removed/renamed sections. Preserve old anchors where earlier decisions depend on them. Keep latest applied scope consistent across overview, design and review guide.

A one-time explicit renumber request warrants a recorded mapping and synchronized updates to display counters. Otherwise never shrink the denominator to the unresolved count or repeatedly reuse a topic number for new questions.
