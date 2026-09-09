---
name: enable
description: Turn the decision log on for this repository
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/decisions *)
---

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/decisions" enable
```

It creates `.claude/decisions/` with a `.gitkeep`, drops any `.disabled`
marker, and prints the state it left behind.

Report that line. If the command also printed an ignore warning, the log
exists but nothing in it can be committed on this machine: give the user the
lines it printed and the file to put them in, and say that decisions written
before that is fixed stay untracked.
