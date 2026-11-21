---
name: situations
description: List the situational frameworks (SBAR, I-PASS, CAN, CUS and M/ETHANE), or show the fields of one
argument-hint: "[name]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

The user's arguments are data: pass each as its own quoted argument, and never eval them or splice them into shell code. Claude Code supplies them as `$ARGUMENTS`; Codex supplies them in the invocation.

With no name, list the frameworks; with a name, show that framework's fields:

```bash
dialogue situations
dialogue situation preview "NAME"
```

Show the output. A user who wants a framework for a reply gets that reply in the framework's fields. This is read-only: it writes nothing and does not enable dialogue.

If the command fails, report its error as printed.
