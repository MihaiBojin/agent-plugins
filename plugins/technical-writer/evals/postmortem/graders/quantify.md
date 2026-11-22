---
type: llm
weight: 1
---

Rule `quantify`: the impact is in numbers, and every number carries its unit.

Pass only if the impact section gives all of these:

- About 41,000 failed checkout requests.
- The peak 5xx rate of 38%.
- The duration of the incident, or its start and end times, with the time zone.

Fail if one is missing, or if a vague qualifier such as "many requests" or "a high error rate" stands in for a number. Quote the text that decides it.
