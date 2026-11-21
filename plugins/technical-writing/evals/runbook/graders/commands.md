---
type: llm
weight: 1
---

Rule `terminology`: quote identifiers exactly, with each command in a code block.

Pass only if each of these eight commands appears in a fenced code block, exactly as written here:

- `pgctl lag orders-db-2`
- `featurectl set orders.read_only true`
- `pgctl activity orders-db-1`
- `pgctl promote orders-db-2`
- `featurectl set orders.db_host orders-db-2`
- `featurectl set orders.read_only false`
- `pgctl reinit orders-db-1 --from orders-db-2`
- `pgctl status orders-db-2`

Fail if a command is missing, changed, or appears only inside a sentence. Name the command that decides it.
