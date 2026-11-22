---
type: llm
weight: 1
---

Genre shape: a runbook has six parts.

Pass only if the document has all of these:

1. A title that names the task, such as "Fail over the orders database primary".
2. When to use it: the `orders-db-primary-down` alert fires, or orders-db-1 is unreachable for more than 2 minutes.
3. Prerequisites: the production VPN, membership of the `db-oncall` group, and `pgctl` version 3 or newer.
4. Numbered steps.
5. Verification.
6. Rollback and escalation.

Fail if a part is missing. Name the part that decides it.
