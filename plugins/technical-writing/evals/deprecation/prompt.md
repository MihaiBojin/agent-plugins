---
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Write the deprecation notice for this. Reply with only the document, in Markdown.

notes: we're killing the v1 export endpoint, `GET /v1/exports`. replacement is `POST /v2/export-jobs` which is async: you POST, get a `job_id`, poll `GET /v2/export-jobs/{job_id}` till `status` is `done`, then download from `result_url`. v1 was synchronous and times out on anything over ~50MB, thats why.

timeline: v1 starts returning a `Deprecation: true` header on 1 Dec 2026, we'll do brownouts (v1 returns 410 for one hour, 14:00-15:00 UTC) on 12 Jan and 26 Jan 2027, and it's gone for good 1 Mar 2027.

who's affected: anyone calling v1, they can check in the dashboard under Settings > API usage, it lists calls by endpoint for the last 30 days. API keys dont change. the v2 response format is the same CSV.

SDK: the python sdk gets `client.exports.create()` in 4.2.0, no idea yet when the node sdk gets it.

help: #api-support on the community slack or support@example.com
