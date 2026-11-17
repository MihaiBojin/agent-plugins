---
name: enable
description: Turn dialogue on for this session and apply its policy
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

```bash
dialogue enable
```

Follow the policy it prints from the next reply on. Apply only that policy, for this session; never enable dialogue because a conversation mentions threads, focus or writing style.

If the command fails, report its error as printed. Never claim a change was saved after a failed command, and never edit or delete the state files to get past an error.
