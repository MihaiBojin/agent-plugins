# Changelog

## 0.2.1 - 2026-11-22

### Changed

Dialogue no longer has the `direct`, `epistemic`, `quantify`, `current_state`, `terminology`, `evidence`, `reasons`, `one_question`, `one_action`, `imperatives`, `conditions` and `notes_not_steps` guidelines, or the precision, evidence and procedures groups, and drops a saved override for any of them. The pyramid, direct and efficient profiles and style `ste` apply fewer rules. The technical-writing and readme plugins keep these rules for documents.

## 0.2.0 - 2026-11-21

### Added

Pull request descriptions have their own skill, `pr-description`, and their own agent. The skill collects why the change exists, what was verified, what was not, and what can break. The agent reads the diff, writes the title and the body, checks each claim against the diff, and returns the facts it could not find. The description opens with what the code does after the merge, then gives the reason, the verification and the risk.

### Changed

A postmortem summary has five sentences at most, one each for what happened, the impact, the duration, the trigger and the current status. A timeline line holds the time, the actor and what the actor did or saw.

### Choices

The main skill never loaded for "write the PR description": 0 of 5 eval runs, against 5 of 5 for the skill of its own. Without a skill the agent opened with a "Why" heading in 5 of 5 runs. With the new format, three runs judged by Claude Fable 5.2 passed 27 of 27 graders.

The agent starts from the diff because the session that made the change remembers the attempts, and writes about them. The agent checks its own draft once. A second agent that only reviews would double the cost: one run on a 49-file pull request cost $0.93 at list price with Claude Fable 5.2 and took 61 seconds.

The agent sets `model: inherit`, so it runs on the session's model. It reads the format and the shared rules through `${CLAUDE_PLUGIN_ROOT}`. The `skills` field would preload them, but Claude Code's documentation does not say how that field names a skill of the same plugin.

The Codex instructions come from Codex's source for `spawn_agent`. Nobody has run them in Codex.

The format differs from the one in the worktrees plugin's `describe-pr` skill, which writes one line per visible change and asks for verification only when the repository does. With both plugins installed, two formats apply to one pull request.

The summary limit was "three to five sentences", and 2 of 5 runs wrote six. With one sentence per named item, 5 of 5 runs wrote five. One timeline in five carried a verdict, "The provider was not the cause"; after the change none of five did.

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
