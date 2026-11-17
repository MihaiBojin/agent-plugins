---
name: disable
description: Stop applying dialogue in this session, keeping its settings and threads
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

```bash
dialogue disable
```

Report the state it printed, then stop following the dialogue policy for the rest of the session. Threads and settings stay saved, and `enable` turns it back on. A request in plain words to stop dialogue or return to normal mode means this command.

If the command fails, report its error as printed. Never claim a change was saved after a failed command, and never edit or delete the state files to get past an error.
