---
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Write the PR description for this change. Reply with only the description, in Markdown.

what I did (branch `retry-budget`, service `notifier`):

commits:

- wip retries
- fix tests
- actually use a budget instead of fixed 5 retries
- revert "wip retries" partial
- lint

so originally the webhook sender retried every failed delivery 5 times with fixed 2s sleep. when a customer endpoint was down for a while we'd pile up retries and that's what caused the queue backlog last week. first I tried exponential backoff only but that still retried dead endpoints forever basically. now: each destination host gets a retry budget, 10% of its requests in a rolling 60s window can be retries (min 3 retries per window so low-volume hosts still get some), backoff is exponential 1s..30s with jitter. when the budget's spent the delivery goes straight to the dead-letter queue with reason `retry_budget_exhausted`. new config `notifier.retry_budget_ratio` default 0.1.

tested: `make test` passes (412 tests, 9 new). ran `make loadtest SCENARIO=dead-endpoint` locally, queue depth peaked at 1,200 vs 48,000 on main. did NOT run the staging soak test, staging is broken today.

risk: customers with flaky endpoints will see more deliveries land in DLQ than before, support should know. flag: `notifier.retry_budget_enabled`, default off, plan is on for 5% of hosts first.
