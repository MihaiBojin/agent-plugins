---
name: status
description: Where a document stands - stage, backend, open threads
argument-hint: "<collection> <number>"
allowed-tools:
  - Bash(node ${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs:*)
  - Bash(node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs":*)
---

`$ARGUMENTS` is the collection directory and the document number. If
`<collection>/<nnnn>.md` exists, the document is archived: report its
frontmatter - status, dates, `superseded_by`, how many errata - and run this
once to confirm the body still matches its hash:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs" verify <collection>/<nnnn>.md
```

Otherwise the document is still in flight and the backend named by
`<collection>/docket.toml` is the truth: read the draft's stage there, and
list its open comment threads - Notion or Drive through the session's MCP,
the pull request's review threads for the git backend. A backend this session
cannot reach means stop and name the missing capability; do not guess at the
stage.

Report stage, backend, and open threads in a few lines. This is read-only:
move nothing, lock nothing, resolve nothing.
