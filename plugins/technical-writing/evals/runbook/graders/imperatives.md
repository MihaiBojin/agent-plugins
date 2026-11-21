---
type: llm
weight: 1
---

Rule `imperatives`: steps use direct imperative verbs.

Pass only if both of these hold:

- Every numbered step starts with an imperative verb, such as "Run", "Set", "Check" or "Page". A condition such as "If the lag is above 30 seconds," may come before the verb.
- No step says "you might want to", "you may want to", "consider", "should" or "please".

Fail if either does not hold. Quote the step that decides it.
