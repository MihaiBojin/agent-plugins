---
type: llm
weight: 1
---

Rule `bluf`: a reader who stops after the summary still has the point.

Pass only if the document opens with a summary of three to five sentences that states all of these:

- What happened: checkout requests failed after deploy 812 changed the format of the session cache key.
- The impact: about 41,000 failed checkout requests, or the peak 5xx rate of 38%.
- The duration, or the start and end times.
- The current status: deploy 812 is rolled back and the service has recovered.

Fail if the summary is missing, runs longer than five sentences, or leaves out one of the four. Quote the summary.
