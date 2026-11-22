---
type: llm
weight: 1
---

Genre shape: each action item says what kind it is and how to verify it.

Pass only if the document has an action item for each of these three, and each item says whether it prevents, detects or mitigates, and how to verify that it is done:

- Make the canary stage mandatory, also when the canary cluster is down.
- Alert on the cache hit rate.
- Find out why the session service did not fall back to the database.

Fail if an item is missing, or lacks its kind or its verification. Name the item that decides it.
