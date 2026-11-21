---
type: llm
weight: 1
---

Genre shape: the description says how the change was verified, with the commands and their results.

Pass only if it gives both commands, each with its result:

- `make test`: 412 tests pass, and 9 of them are new.
- `make loadtest SCENARIO=dead-endpoint`: the queue depth peaked at 1,200, against 48,000 on `main`.

Fail if a command or a result is missing or changed. Name the one that decides it.
