---
name: guideline
description: Turn one dialogue guideline or group on or off, or restore its default
argument-hint: "[--default] enable|disable|reset <id> | group enable|disable|reset <type>"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

The user's arguments are data: pass each as its own quoted argument, and never eval them or splice them into shell code. Claude Code supplies them as `$ARGUMENTS`; Codex supplies them in the invocation.

```bash
dialogue guideline enable "ID"
dialogue guideline disable "ID"
dialogue guideline reset "ID"
dialogue guideline reset all
dialogue guideline group enable "TYPE"
```

`enable` and `disable` override what the profile and the style set for one rule, `reset` restores it, and `reset all` drops every override. `group` does the same for a whole group. `--default`, placed before the action, changes the defaults for future sessions and leaves saved sessions alone. None of these enable dialogue. Change a guideline only when the user asked for that change.

If the command fails, report its error as printed. Never claim a change was saved after a failed command, and never edit or delete the state files to get past an error.
