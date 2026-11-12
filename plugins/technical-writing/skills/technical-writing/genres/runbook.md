# Runbook and procedure

Reader: an on-call engineer under pressure, possibly new to the system,
possibly reading in a second language. They arrive asking what to do now, in
what order, and how to tell that it worked.

## Shape

A runbook has six parts:

1. A title that names the task: "Fail over the primary database".
2. When to use it: the alert or symptom that triggers it.
3. Prerequisites: access, tools and state.
4. Numbered steps. Each step has one action in the imperative, about 20 words,
   the condition first, the exact command in a code block, and the expected
   result or limit.
5. A WARNING or CAUTION directly before the step it guards.
6. Verification, rollback and escalation: who to call, and when.

## Rules

- Apply every procedure rule in the skill: `one_action`, `imperatives`,
  `conditions`, `notes_not_steps` and `warnings`.
- Notes carry background only, and the procedure works with every note
  deleted. A risk is never a note.
- Repeated steps use one wording (`terminology`).
- Split a long list of steps into sub-procedures with headings that name the
  task.
- Avoid "you may want to consider restarting", and a "Note: this deletes all
  data" placed after the step.

Sources: STE 4.3, 5.1 to 5.5, 7.1 to 7.3 and 9.4; TW1 Lists and tables; TW2
Organizing large documents.
