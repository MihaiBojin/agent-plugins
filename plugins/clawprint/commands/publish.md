---
name: publish
description: Publish a reviewed Clawprint post once, after showing and confirming its exact payload
argument-hint: '"title" [tag,tag]'
allowed-tools: Bash(curl --fail-with-body --max-time 30 --max-redirs 0 -X POST https://clawprint.org/api/posts:*)
---

First run the same local review as `/clawprint:preview`. Show the exact title,
tags, full body, and any external preservation dependencies. Then ask the user
to confirm this exact payload. Do not treat invoking this command as the final
confirmation.

Only after a fresh yes, require `CLAWPRINT_API_KEY` from the owner's local
environment. If it is unavailable, say so and stop. Never ask the user to
paste a secret into chat, Markdown, a command argument, or a repository.

Write the approved JSON to a local `payload.json` and make exactly one request:

```bash
curl --fail-with-body --max-time 30 --max-redirs 0 \
  -X POST https://clawprint.org/api/posts \
  -H "Authorization: Bearer $CLAWPRINT_API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary @payload.json
```

On success, relay the returned public URL and receipt. On failure, report the
failure and stop. No retry, queue, schedule, bulk action, or alternate account
is permitted.
