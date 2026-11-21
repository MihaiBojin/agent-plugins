---
type: llm
weight: 1
---

Rule `bluf`: a reader who stops after the summary can still respond.

Pass only if the summary, before any other section, states all of these:

- The problem: the nightly invoice run takes 5 hours 40 minutes against a 6-hour window, or it restarts from zero when its VM fails.
- The proposal: split the run into one job per customer on the `workq` job queue.
- The ask: reviewers approve the approach, and someone from finance answers the question about invoice numbering.

Fail if one of the three is missing from the summary. The ask is the one most often left out. Quote the summary.
