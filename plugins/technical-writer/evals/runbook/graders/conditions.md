---
type: llm
weight: 1
---

Rule `conditions`: the condition comes before the action.

Pass only if both of these hold:

- The lag check puts its condition first: if the replication lag is above 30 seconds, stop and page `dba-escalation`.
- The reinitialization puts its condition first: if orders-db-1 is unreachable, skip the step and open a ticket for the DBA team.

Fail if either sentence puts the action before its condition, or if either branch is missing. Quote the sentence that decides it.
