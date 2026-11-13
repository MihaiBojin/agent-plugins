# Changelog

## 0.1.2 - 2026-11-13

### Fixed

Release-note requests use `release:write` for one change and `release:prepare` for a release when the release plugin is installed. Both skills read the shared rules internally.

## 0.1.1 - 2026-11-13

With the `release` plugin installed, the release-note genre sends the agent
to its `write` skill. The genre named the `release-notes` plugin, which
`release` replaced, so the agent wrote release notes from the genre file
instead.

## 0.1.0 - 2026-11-12

The first release: one skill that picks the shape of a piece of software writing from its reader, and sentence rules for all of it. A genre file covers each of bug reports, postmortems, incident updates, design docs and RFCs, decision records, runbooks, error messages, PR descriptions, commit messages, code comments, READMEs and tutorials, status updates, review comments, deprecation notices, decision requests, escalations and handoffs, agent briefs, release notes, and short forms such as alt text and CLI help. The agent loads the skill when asked to write or review one of them, and reads only the genre file it needs.

The rules adapt ASD-STE100 Issue 9 and four of Google's technical writing courses, and each one has an ID that a review can cite. Twenty-two of them are the dialogue plugin's guidelines, with the same IDs and first lines. Four cover documents only: `self_edit`, `no_visual_only`, `navigable` and `inclusive_language`.

### Choices

The 22 shared rules are copies, and `__tests__/shared-rules.test.mjs` keeps each first line identical to dialogue's. A plugin cannot read another plugin's files. Having dialogue tell the agent to load this skill instead would make every chat reply depend on the model invoking it after each compaction, and dialogue installed alone would lose those rules.

The skill is model-invoked, unlike dialogue, so an agent asked for a postmortem loads it without being told. Each genre lives in its own file so that only the one in use enters the context.

The release-note genre states the release-notes plugin's rules in brief and defers to that plugin, which owns them.

Dialogue's `plain_punctuation` and `no_frame` stay out of the shared rules. Google's courses allow em-dashes, and a repository that bans them says so in its own rules, which outrank the skill. `no_frame` would forbid the summary that a postmortem and a design doc open with.

ASD-STE100 may not be reproduced, so the skill cites its rule numbers and paraphrases them. The Google courses are CC BY 4.0, and `NOTICE` carries their attribution.
