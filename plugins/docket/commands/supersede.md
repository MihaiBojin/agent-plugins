---
name: supersede
description: Point a frozen document at the successor that replaces it
argument-hint: "<collection> <old-number> <new-number>"
allowed-tools:
  - Bash(node ${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs:*)
  - Bash(node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs":*)
---

`$ARGUMENTS` is the collection directory, the old number, the new number. The
successor freezes first: if `<collection>/<new>.md` is not in the archive,
stop and say to `/docket:freeze` it before anything points at it.

Holding both `doc/<collection>/<old>` and `doc/<collection>/<new>` when the
mutex plugin is available - taken in lexicographic order, with a plain
warning when it is not - run these two, in this order:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs" set <collection>/<old>.md superseded_by <new>
node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs" set <collection>/<old>.md status superseded
```

The old body is untouched - superseding is a pointer, and the CI check would
refuse anything more. Commit the change to the archive and say in one line
which document now supersedes which. Nothing else: no edits to either body,
no errata, no cleanup.
