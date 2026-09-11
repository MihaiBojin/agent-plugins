---
name: rewrite
description: Audit a README, rewrite it in place, then audit the rewrite
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/readme *)
---

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/readme" all $ARGUMENTS
```

`$ARGUMENTS` is the README to rewrite when the user named one, and `README.md`
in the working directory otherwise.

Run all four passes of the `readme` skill. Print the audit before touching the
file, so the edits arrive with the reasons already stated, then rewrite in
place.

Two things the rewrite has to do before it deletes anything. Find what points
at the section being removed, prose references included, and move those with
the content. Check that whatever is being cut as "documented elsewhere" is
documented elsewhere.

Finish with the self-audit: the same checks over the new draft, plus the
humanizer patterns over prose written minutes ago. Report what it found, even
when that is nothing.
