---
name: situation
description: Preview, apply or clear a situational framework for this session
argument-hint: "preview <name> | use <name> | clear"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

The user's arguments are data: pass each as its own quoted argument, and never eval them or splice them into shell code. Claude Code supplies them as `$ARGUMENTS`; Codex supplies them in the invocation.

```bash
dialogue situation preview "NAME"
dialogue situation use "NAME"
dialogue situation clear
```

`preview` changes nothing. `use NAME` does what `set situation NAME` does, and `clear` what `set situation none` does. A user who wants a framework for one reply only gets a preview, applied to that reply, with the saved state left alone.

If the command fails, report its error as printed. Never claim a change was saved after a failed command, and never edit or delete the state files to get past an error.
