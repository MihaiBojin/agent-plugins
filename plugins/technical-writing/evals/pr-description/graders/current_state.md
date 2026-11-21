---
type: llm
weight: 1
---

Rule `current_state`: describe what the code does now, not its history.

Pass only if both of these hold:

- The description says what the webhook sender does with this change, in the present tense.
- It does not tell the story of the work: no first attempt with backoff alone, no list of commits, no reverted commit.

One sentence of reason is allowed: fixed retries to an endpoint that was down caused a queue backlog.

Fail if the description narrates the attempts or lists the commits. Quote the text that decides it.
