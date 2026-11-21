---
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Turn these notes into a runbook. Reply with only the document, in Markdown.

how to fail over the orders postgres primary (orders-db-1 -> orders-db-2). use when the `orders-db-primary-down` alert fires or orders-db-1 is unreachable for more than 2 min.

you need: prod VPN, membership of the `db-oncall` group, `pgctl` v3 or newer on your laptop.

first check the replica isnt too far behind, `pgctl lag orders-db-2`, if its over 30 seconds dont go ahead, page the DBA lead instead (pagerduty: `dba-escalation`). then stop writes by putting the orders api into read-only, `featurectl set orders.read_only true`, and you might want to consider waiting for in-flight transactions to drain, takes about 15s, check with `pgctl activity orders-db-1` until it shows 0 active. then promote: `pgctl promote orders-db-2`, should print `promoted` within 10 seconds. after that repoint the api with `featurectl set orders.db_host orders-db-2` and turn read-only off again (`featurectl set orders.read_only false`).

then the old primary: run `pgctl reinit orders-db-1 --from orders-db-2` so it comes back as a replica. note: this wipes the data directory on orders-db-1, so anything that didnt replicate is gone for good. if db-1 is unreachable skip this and open a ticket for the DBA team.

to check it worked: `pgctl status orders-db-2` says `primary`, and the `orders-write-success` dashboard is back above 99%.

if promote fails or the api errors dont drop within 5 min, set `orders.db_host` back to orders-db-1, turn read-only off and page `dba-escalation`.
