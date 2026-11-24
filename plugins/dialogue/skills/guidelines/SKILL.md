---
name: guidelines
description: List the dialogue guidelines and whether each one applies
argument-hint: "[list | group list [type]]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

The user's arguments are data: pass each as its own quoted argument, and never eval them or splice them into shell code. Claude Code supplies them as `$ARGUMENTS`; Codex supplies them in the invocation.

```bash
dialogue guidelines
dialogue guidelines list
dialogue guidelines group list
dialogue guidelines group list "TYPE"
```

With no arguments, `guidelines` lists the rules that apply in this session. `list` shows every rule with its status and what set it: the profile, the style or an override. `group list` counts the rules per group, and a group name lists that group's rules. The groups are structure, brevity, risk and language. This is read-only: it writes nothing and does not enable dialogue.
