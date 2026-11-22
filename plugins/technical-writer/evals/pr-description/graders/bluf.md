---
type: llm
weight: 1
---

Rule `bluf`: the first paragraph says what the code does.

A line that starts "Title:" may come before the body. The first paragraph is the first text after it, and no heading stands above that paragraph.

Pass only if the first paragraph states all of these:

- Each destination host has a retry budget.
- The budget is 10% of the host's requests in a rolling 60-second window, with at least 3 retries per window.
- When the budget is spent, the delivery goes to the dead-letter queue with the reason `retry_budget_exhausted`.

Fail if the first paragraph is background, history or a greeting, or leaves out one of the three. Quote the first paragraph.
