---
name: enable
description: Turn the decision log on for this repository
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/decisions *)
---

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/decisions" enable
```

It creates `.decisions/` at the repository root with a `.gitkeep`, drops any
`.disabled` marker, and prints the state it left behind.

Report that line. If the command also printed an ignore warning, the log
exists but nothing in it can be committed here: pass on the `git check-ignore`
command it named, and say that decisions written before the rule is fixed stay
untracked.
