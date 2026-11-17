---
name: disable
description: Stop applying dialogue in this session, keeping its settings and threads
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
  - Bash("${CLAUDE_PLUGIN_ROOT}/bin/dialogue" *)
---

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/dialogue" --client claude --session "${CLAUDE_SESSION_ID}" disable
```

In Codex, pass `--client codex` and omit `--session`: the tool reads
`CODEX_THREAD_ID`.

Report the state it printed, then stop following the dialogue policy for the
rest of the session. Threads and settings stay saved, and `/dialogue:dialogue`
turns it back on.
