---
type: llm
weight: 1
---

Rule `epistemic`: name missing evidence instead of filling the gap.

The source notes hold these numbers and no others: 5 fixed retries with a 2-second sleep before this change, a budget of 10% in a rolling 60-second window, a minimum of 3 retries per window, backoff from 1 second to 30 seconds with jitter, a default of 0.1 for `notifier.retry_budget_ratio`, 412 tests of which 9 are new, a queue depth of 1,200 against 48,000 on `main`, and 5% of hosts.

Pass only if every number, test, ticket, date and person in the description comes from the notes or from arithmetic on them.

Fail if the description states a metric, a test run, a ticket, a date, a reviewer or a rollout stage that the notes do not support. Quote it.
