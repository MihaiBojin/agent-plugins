---
type: llm
weight: 1
---

Rule `one_action`: one executable action per numbered step.

Pass only if each numbered step holds one action. Each of these pairs is two steps:

- Set the orders API to read-only, then wait for the in-flight transactions to drain.
- Point the API at orders-db-2, then turn read-only off.

Fail if one step joins two commands or two actions. Quote the step that decides it.
