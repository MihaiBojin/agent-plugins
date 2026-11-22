---
type: llm
weight: 1
---

Rule `quantify`: numbers where there are numbers, each with its unit.

Pass only if the document gives all of these:

- The run time today: 5 hours 40 minutes.
- The benchmark: 20 workers finish in 48 minutes.
- The cost: $310 per month, against $95 per month for the VM.

Fail if one is missing, or if a vague qualifier such as "much faster" or "more expensive" stands in for it. Quote the text that decides it.
