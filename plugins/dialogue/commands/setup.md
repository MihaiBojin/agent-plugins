---
name: setup
description: Configure dialogue for this session by answering three questions
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
  - Bash("${CLAUDE_PLUGIN_ROOT}/bin/dialogue" *)
---

Print the options. This needs no session ID and writes nothing:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/dialogue" --client claude setup
```

In Codex, pass `--client codex`.

Ask **one question at a time**, using the options and descriptions from that
output:

1. **Comms**: `pyramid`, `direct`, `efficient`, `plain`, or `custom` (start
   with no rules enabled and turn guidelines on one at a time). Presets only
   set baseline guidelines, and individual overrides take final precedence.
2. **Style**: `plain` or `ste` (STE-inspired, not ASD-STE100 compliant). `ste`
   adds the ASD-STE100-derived guidelines.
3. **Workflow**: `quiet`, `automatic`, `verified`, `status`, `escalation`,
   `handoff`, `safety`, or `incident`. A workflow selects both situational
   formatting and signals, and each stays editable with `/dialogue:set`.

Hold the answers in the conversation until the third one. Run nothing that
changes state during questions 1 and 2. After question 3, save all three at
once:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/dialogue" --client claude --session "${CLAUDE_SESSION_ID}" setup apply --comms VALUE --style VALUE --workflow VALUE
```

In Codex, pass `--client codex` and omit `--session`: the tool reads
`CODEX_THREAD_ID`.

The tool validates the values and writes the four underlying settings
atomically. Show the short configuration it prints. Setup does not enable
dialogue. If the user cancels, write nothing. If an answer is unclear, ask that
question again and no other.
