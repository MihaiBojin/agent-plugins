---
type: llm
weight: 1
---

Genre shape: the notice gives every date, in full.

Pass only if the document gives all of these, each date with its year:

- 1 December 2026: responses from v1 carry the `Deprecation: true` header.
- 12 January 2027 and 26 January 2027, from 14:00 to 15:00 UTC: v1 returns 410.
- 1 March 2027: v1 is removed.

Fail if a date is missing, has no year, or if the two one-hour windows have no time zone. Name the date that decides it.
