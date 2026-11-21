---
type: llm
weight: 1
---

Rule `warnings`: a WARNING comes before the step it guards.

`pgctl reinit orders-db-1 --from orders-db-2` deletes the data directory on orders-db-1. Data that did not replicate is lost, and nothing recovers it.

Pass only if all of these hold:

- The word WARNING, in capitals, comes directly before the step that runs `pgctl reinit`.
- The warning states the consequence: the data directory is deleted and data that did not replicate is lost.
- The risk appears nowhere as a note, and nowhere after the command.

Fail if the document uses CAUTION for this step, puts the risk in a note, or puts it after the command. Quote the text that decides it.
