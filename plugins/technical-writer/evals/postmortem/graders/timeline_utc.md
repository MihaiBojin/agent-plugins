---
type: llm
weight: 1
---

Genre shape: the timeline has one event per line, in UTC and the past tense.

The notes give Pacific times, which are UTC-8. The correct UTC times are 17:12 for the merge of PR 4411, 17:20 for deploy 812, 17:26 for the alert, 18:04 for the start of the rollback, 18:11 for the 5xx rate under 1%, and 18:30 for the all clear.

Pass only if all of these hold:

- Each timeline line carries a UTC time, and the six times above are right.
- Each line holds one event.
- Each line is in the past tense.

Fail if the timeline uses Pacific times, gets a conversion wrong, or mixes tenses. Quote the line that decides it.
