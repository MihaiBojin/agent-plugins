---
type: llm
weight: 1
---

Rule `one_action`: the expected result or limit is in the same step as the action.

Pass only if each of these results appears in the step that runs its command:

- `pgctl activity orders-db-1` shows 0 active transactions.
- `pgctl promote orders-db-2` prints `promoted` within 10 seconds.
- `pgctl status orders-db-2` reports `primary`.

Fail if a result is missing, or sits in a different step or section from its command. Name the result that decides it.
