---
name: situations
description: List the situational frameworks: SBAR, I-PASS, CAN, CUS and M/ETHANE
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

```bash
dialogue situations
```

Show the list. `situation preview NAME` shows one in full, and `set situation NAME` applies it. This is read-only: it writes nothing and does not enable dialogue.
