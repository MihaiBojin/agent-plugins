# Release note

The
[release plugin](https://github.com/releasetools/agent-plugins/tree/main/plugins/release#readme)
owns this genre. When it is installed, use `release:write` for one change's
note and `release:prepare` for a release's changelog entry. Both skills read
the shared release-note rules internally. This file states those rules in
brief for use when the plugin is absent.

Reader: somebody on the previous version, deciding whether this release
affects them.

## Rules

A release note follows six rules:

- Write an entry only for a change that a user can observe.
- Say what changed and what the reader does about it.
- A fix names the symptom, so that someone who hit it recognizes it.
- Breaking changes go first, and each one says what to do instead.
- Leave out pull request numbers, commit hashes and internal names.
- Use the exact name of a flag (`terminology`), give numbers and limits
  (`quantify`), and use plain words for readers outside the team
  (`plain_words`).

For a large release, Google's unit on LLMs suggests a layout: an introductory
paragraph, a table of one-line summaries, then a subsection per item with the
problem and any workaround.

Sources: the release plugin's
[release-note rules](https://github.com/releasetools/agent-plugins/blob/main/plugins/release/references/release-notes.md);
TW2 Using LLMs.
