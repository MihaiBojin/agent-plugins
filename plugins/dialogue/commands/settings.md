---
name: settings
description: Show every dialogue setting for this session, its default and what it does
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
  - Bash("${CLAUDE_PLUGIN_ROOT}/bin/dialogue" *)
---

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/dialogue" --client claude --session "${CLAUDE_SESSION_ID}" settings
```

In Codex, pass `--client codex` and omit `--session`: the tool reads
`CODEX_THREAD_ID`.

Show the table it prints. This never enables dialogue and writes nothing.
