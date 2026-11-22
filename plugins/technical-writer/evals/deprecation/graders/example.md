---
type: llm
weight: 1
---

Genre rule: a breaking change says what to do instead, with an example.

Pass only if a code block shows the replacement flow with all three calls:

- `POST /v2/export-jobs`, which returns a `job_id`.
- `GET /v2/export-jobs/{job_id}`, polled until `status` is `done`.
- The download from `result_url`.

Fail if the document has no code block for the flow, or if the example leaves out a call. Name the call that decides it.
