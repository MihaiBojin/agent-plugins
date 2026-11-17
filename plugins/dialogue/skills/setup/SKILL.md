---
name: setup
description: Configure dialogue for this session by answering three questions
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

Print the options. This step writes nothing and needs no session ID:

```bash
dialogue setup
```

Ask **one question at a time**, with the options and descriptions from that output:

1. **Comms**: `pyramid`, `direct`, `efficient`, `plain`, or `custom` (start with no rules enabled and turn guidelines on one at a time). Presets only set baseline guidelines, and individual overrides take final precedence.
2. **Style**: `plain` or `ste` (STE-inspired, not ASD-STE100 compliant). `ste` adds the ASD-STE100-derived guidelines.
3. **Workflow**: `quiet`, `automatic`, `verified`, `status`, `escalation`, `handoff`, `safety`, or `incident`. A workflow selects both situational formatting and signals, and each stays editable with `set`.

Hold the answers in the conversation until the third one. Run nothing that changes state during questions 1 and 2. After question 3, save all three at once:

```bash
dialogue setup apply --comms VALUE --style VALUE --workflow VALUE
```

The tool validates the values and writes the four underlying settings atomically. Show the short configuration it prints. Setup does not enable dialogue. If the user cancels, write nothing. If an answer is unclear, ask that question again and no other.

If the command fails, report its error as printed. Never claim a change was saved after a failed command, and never edit or delete the state files to get past an error.
