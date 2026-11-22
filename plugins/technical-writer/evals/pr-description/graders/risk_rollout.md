---
type: llm
weight: 1
---

Genre shape: the description states the risk and the rollout.

Pass only if it states all of these:

- The risk: customers with unreliable endpoints get more deliveries in the dead-letter queue, and the support team needs to know.
- The flag `notifier.retry_budget_enabled`, which is off by default.
- The first stage of the rollout: 5% of hosts.

Fail if one is missing. Name the one that decides it.
