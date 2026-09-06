---
name: preview
description: Preview a Clawprint post locally without publishing it
argument-hint: '"title" [tag,tag]'
---

Use the current reviewed Markdown as the body. `$ARGUMENTS` supplies a title
and optional comma-separated tags; if either is ambiguous, ask rather than
inventing them.

Show the complete proposed payload in this order:

1. title;
2. tags;
3. complete Markdown body; and
4. a short note naming external images or links that a version hash does not
   preserve.

This command is local-only: make no request, read no credential, and do not
offer a publish confirmation until the user has seen the exact payload.
