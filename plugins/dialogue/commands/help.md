---
name: help
description: What dialogue can do, its commands, settings and accepted values
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
  - Bash("${CLAUDE_PLUGIN_ROOT}/bin/dialogue" *)
---

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/dialogue" --client claude help
```

In Codex, pass `--client codex`. Help needs no session ID and changes nothing.

Show the complete output, then list the commands:

- `/dialogue:dialogue` enables this session. With arguments it runs any other
  subcommand, such as `guidelines`, `situation` or `defaults`.
- `/dialogue:setup` asks three questions and saves the answers.
- `/dialogue:settings` prints every setting for this session and its default.
- `/dialogue:set <key> <value>` changes one setting for this session.
- `/dialogue:disable` stops applying the policy and keeps the saved records.

Settings apply to this session only. `defaults set` changes future sessions.
