# Problem statement and bug report

Reader: the engineer who will reproduce and fix the problem, or the person
triaging it. They arrive asking what is broken, for whom, how badly, and
whether they can reproduce it. They leave to reproduce, prioritize or assign
it.

## Shape

A report has eight fields:

1. Summary: one sentence with the symptom, where it happens, and the impact.
2. Impact: who and how many, since when, with numbers.
3. Steps to reproduce: numbered imperative steps, each condition first.
4. Expected and actual results, with the error text, exit code or status
   quoted exactly.
5. Environment: versions, configuration and commit.
6. Evidence: logs, traces, and screenshots with a caption that states the
   takeaway.
7. Known, suspected and unknown, kept apart (`epistemic`).
8. Workaround, if one exists.

## Rules

- Report the offending input and the constraint it broke. Google's model is
  "the specified bid ($5) is below the minimum bid ($8)".
- Title the report with the symptom, not the suspected cause.
- While the cause is open, say that the actor is unknown instead of guessing
  one (`direct`).
- Write one problem per report.
- Avoid "doesn't work", "is broken", and a guessed root cause as the title.

Sources: Google Writing Helpful Error Messages, for the cause, the invalid
input and the constraint; STE 3.6, 4.1; practice, for the field list.
