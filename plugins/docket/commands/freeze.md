---
name: freeze
description: Check the exit criterion and freeze a document into the archive
argument-hint: "<collection> <number>"
allowed-tools:
  - Bash(node ${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs:*)
  - Bash(node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs":*)
---

`$ARGUMENTS` is the collection directory and the document number. Hold
`doc/<collection>/<nnnn>` through the mutex plugin when the session has it;
warn plainly when it does not.

First the exit criterion, from the backend named by `<collection>/docket.toml`:
every comment thread resolved or answered, surviving dissent captured in the
document's own text. The docket skill judges what counts as resolved; an
unresolved thread stops this command with a list of what is open, and a
backend this session cannot reach stops it with the missing capability's
name.

Then export the body to a file and run this once:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs" freeze <collection> <nnnn> \
  --title "<title>" --created <YYYY-MM-DD> --backend <ref> --body <exported-file>
```

`--created` is the date the draft first existed, read from the backend: the
Notion page's or the Google Doc's creation time, or the first commit on the
draft's branch for git. Ask the user when the backend cannot say. The helper
checks the shape and nothing else, so a guessed date archives as fact.

`--backend` is the draft's address - `notion/page/<id>`, `gdocs/<id>`, or the
PR URL for the git backend, where the draft file is replaced by this
assembled one and the merge is the freeze. Follow with `verify` on the
written file, commit it to the archive, and apply the backend's enforcement:
`is_locked: true` on a Notion page, Drive `contentRestrictions` read-only for
Google Docs (verify the session's MCP exposes it), nothing extra for git.

Report the file, the hash, and what now enforces the freeze, in a few lines.
