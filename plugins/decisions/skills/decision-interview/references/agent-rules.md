# Optional agent-rules snippet

Use this only when the user wants the preference in an existing agent-rules file. Preserve unrelated rules and adapt paths to the project. It is an alternative entry point, not a requirement to modify global configuration.

```markdown
## Guided planning preference

For substantial design/requirements discussions, ask one material question at a time, usually with two or three concrete options and a brief tradeoff explanation. Show a stable question ID/allocated total and the remaining count, computed from the saved queue. Do not impose an interview on straightforward work.

Honor existing logging switches and disk-output authorization; keep state in conversation when no saved package was requested. Persist authorized answers into the current design and decision history before advancing. Distinguish accepted decisions, applied engineering defaults, proposals, delegated implementation choices and measured results. Remove solved asks from the open queue while preserving their disposition/history. Clarification is not selection; “next” without an answer means defer, not approve.

Keep the interview short: reuse existing answers, combine overlapping topics, choose simple defaults where judgment is delegated, and move implementation details or benchmark tuning out of the questionnaire. Keep unanswered dependencies visible and explain reductions or numbering jumps.

When asked to prepare a design for review, provide an entry point listing unanswered and discarded questions, current scope and next steps. Honor any explicit review-before-implementation gate. Commit or push only when authorized, verify the result, and do not start implementation merely because the interview or planning commit is complete.
```
