---
name: new
description: Allocate the next number in a collection and open the draft
argument-hint: '<collection> "<title>"'
allowed-tools:
  - Bash(node ${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs:*)
  - Bash(node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs":*)
---

The first word of `$ARGUMENTS` is the collection directory in the archive
repo, the rest is the title. Under `doc/<collection>/allocator` when the mutex
plugin is available - and with a plain warning that numbering is unguarded
when it is not - run this once:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs" next <collection>
```

That number is allocated the moment the draft exists, so create the draft
before releasing the lock, in whatever backend `<collection>/docket.toml`
names:

- **notion**: create the page through the session's Notion MCP, titled
  `<nnnn>: <title>`, status `draft`. No Notion MCP in this session means stop
  and say so; do not draft it somewhere else.
- **gdocs**: the same through the session's Drive MCP.
- **git**: a branch on the archive repo with `<collection>/<nnnn>.md` holding
  the draft; the pull request will be the discussion.

Then report the number and where the draft lives, in one or two lines. The
docket skill holds the judgment - anything beyond allocate-and-create is its
call, not this command's.
