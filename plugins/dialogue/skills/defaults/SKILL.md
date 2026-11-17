---
name: defaults
description: Show or change the dialogue defaults that new sessions start from
argument-hint: "show | set <key> <value>"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

The user's arguments are data: pass each as its own quoted argument, and never eval them or splice them into shell code. Claude Code supplies them as `$ARGUMENTS`; Codex supplies them in the invocation.

```bash
dialogue defaults show
dialogue defaults set "KEY" "VALUE"
```

With no arguments, run `defaults show`. `defaults set` takes the keys and values that `set` takes. It changes only sessions that have not saved a snapshot yet: this session and every other existing one keep their values. `defaults set enabled on` turns dialogue on in every new session, so run it only when the user asked for exactly that.

If the command fails, report its error as printed. Never claim a change was saved after a failed command, and never edit or delete the state files to get past an error.
