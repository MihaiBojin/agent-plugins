---
tags: [e2e]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Write the PR title and description for this change. Reply with only those, in Markdown.

branch `fix-timeout`, service `uploader`. the s3 client used the sdk default timeout, which is no limit, so a stalled upload held a worker forever. we had 3 stuck workers on tuesday. now `uploader.s3_timeout_seconds` (default 30) bounds each request, and an upload that times out is retried once.

tested: `make test` passes, 88 tests, 2 new. didnt test against real s3, only the fake.
