---
type: regex
pattern: '\b(originally|previously|first tried|at first|wip retries|revert(ed)?)\b'
flags: i
match: not_contains
---

Rule `current_state`, as a pattern: none of the words that narrate history appear.
