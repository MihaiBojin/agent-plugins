---
type: llm
weight: 1
---

Rule `bluf`: the first sentences say what changes and by when.

Pass only if the first paragraph states all of these:

- `GET /v1/exports` is removed.
- The removal date: 1 March 2027.
- The replacement: `POST /v2/export-jobs`.

Fail if the first paragraph is background, a greeting or a reason, or leaves out one of the three. Quote the first paragraph.
