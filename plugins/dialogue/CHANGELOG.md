# Changelog

## 0.1.2

Codex labels the startup hook as `loading dialogue settings`. Its skill picker lists Dialogue subcommands; `$dialogue:dialogue help` shows their syntax and accepted settings.

## 0.1.1

Claude Code shows subcommand syntax in the dialogue autocomplete hint. Invoke dialogue with `help`, `--help`, or `-h` to see commands and accepted settings without changing session state.

## 0.1.0

Enable response style and persistent threads explicitly in Claude Code or Codex. Each session keeps its settings across resume and compaction. The settings command shows session values, saved defaults, and explanations. Focus mode defers unrelated issues, and compact replies show a count of other open threads with commands to reveal them.

### Choices

Python's standard library handles structured records without third-party packages. Client-specific hook configurations identify the client explicitly; session IDs keep records separate. Settings and thread data live outside the plugin cache so updates retain them. Full agent-rules remains available through its installer, while its limited profile avoids overlapping conversation instructions.
