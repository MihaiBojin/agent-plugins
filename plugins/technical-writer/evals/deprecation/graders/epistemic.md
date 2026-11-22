---
type: llm
weight: 1
---

Rule `epistemic`: name missing evidence instead of filling the gap.

The Python SDK supports the replacement from version 4.2.0, with `client.exports.create()`. Nobody knows yet when the Node SDK supports it.

Pass only if the document says that the date or the version for the Node SDK is not known yet.

Fail if it gives a version or a date for the Node SDK, or leaves the Node SDK out. Quote the text that decides it.
