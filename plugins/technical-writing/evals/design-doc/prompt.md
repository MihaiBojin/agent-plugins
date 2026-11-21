---
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Draft the design doc for this proposal. Reply with only the document, in Markdown.

notes:

problem: nightly invoice generation runs as one cron job on a single VM (`billing-cron-1`). it takes 5h 40m now for ~212,000 invoices, was 2h a year ago. it has to finish before 06:00 UTC when the email send starts, it starts at 00:00 so we have 20 min of slack left. if the VM dies mid-run we restart from zero, happened twice in Q1 2026 (14 Jan, 9 Mar), both times invoices went out late.

proposal: split the run into per-customer jobs on the existing job queue (we already run `workq` for image processing). a planner enqueues one job per customer at 00:00, 20 workers pull jobs, each job is idempotent keyed on (customer_id, billing_period). benchmark on staging with a copy of prod data: 20 workers finish in 48 min. failed jobs retry 3 times then go to a dead-letter queue and page billing on-call.

considered: (a) bigger VM, tried 2x cpu on staging, only got it down to 4h 50m because the job is single threaded. (b) rewrite the cron job to be multi-threaded in place, would still restart from zero on a crash. (c) buy a billing SaaS, quote was $180k/yr, and it cant do our custom tax rules.

cost: 20 workers for ~1h/night, infra estimate is $310/month vs $95/month for the current VM.

risk: the invoice numbering has to stay gapless and sequential per legal entity, right now thats guaranteed because its one process. dont have a design for that yet, maybe a db sequence per entity? need finance + legal to confirm what "gapless" has to mean.

not doing: changing the invoice template, changing the email send, real-time invoicing.

rollout: run both in parallel for 2 billing cycles in shadow mode and diff the output, then cut over. no date yet.

want from reviewers: approve the approach, and somebody from finance to answer the numbering question.
