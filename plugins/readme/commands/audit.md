---
name: audit
description: Report what a README claims that the repository no longer does
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/readme *)
---

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/readme" all $ARGUMENTS
```

`$ARGUMENTS` is the README to read when the user named one, and `README.md` in
the working directory otherwise.

Then run passes 1 and 2 of the `readme` skill over the same file: measure it
against comparable projects, and check every claim in it by running the thing
it describes. The `--help` output, the file the tool actually writes, and the
quickstart run in a sandbox are where the findings are.

Report the findings worst first, in the five groups the skill names, each with
the evidence that produced it. Change nothing, and say at the end what a
rewrite would do.
