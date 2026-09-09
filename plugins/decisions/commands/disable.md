---
name: disable
description: Stop logging decisions here, keeping the ones already recorded
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/decisions *)
---

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/decisions" disable
```

A log with topic files in it gets a `.disabled` marker and keeps every file. An
empty log is removed. Nothing already recorded is deleted either way.

Report the state it printed. Deleting the record is a separate thing the user
has to ask for by name.
