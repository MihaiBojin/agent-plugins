---
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Write the postmortem for this incident. Reply with only the document, in Markdown.

These are my raw notes from the incident channel. All times are Pacific (PST, UTC-8), on 3 March 2026.

- 09:12 dana merged PR 4411 (checkout-api), changes the session cache key from `user:{id}` to `u:{id}:{region}`
- 09:20 deploy 812 goes out to all regions at once, canary was skipped bc the canary cluster was down for maintenance
- 09:26 pagerduty fires `checkout-5xx-rate` (threshold 2%), 5xx at 31% at that point. sam acks at 09:29
- 09:31ish support says customers getting logged out mid checkout
- 09:40 sam thinks its the payments provider, opens a ticket with them. it wasnt them
- 09:58 priya spots that every request misses the session cache, redis hit rate went 94% -> 3%
- 10:04 rollback of deploy 812 started
- 10:11 5xx back under 1%, hit rate recovering
- 10:30 all clear called
- peak 5xx was 38% at 09:44
- about 41,000 checkout requests failed. no idea yet how many orders we actually lost, finance is looking
- we still dont know why the session service didnt fall back to the db when the cache missed, the fallback path exists. maybe its the timeout? nobody has checked
- root cause is basically human error, dana should have been more careful and tested with a prod-like cache
- todo: make canary mandatory (even when the canary cluster is down), alert on cache hit rate, figure out the fallback thing. no owners yet
