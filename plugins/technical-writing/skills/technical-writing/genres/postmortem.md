# Postmortem

Reader: engineers and leads who were not in the incident, and engineers years
later. They arrive asking what happened, how bad it was, why, and what stops
it from happening again. They leave to fund and do the action items.

## Shape

A postmortem has nine sections:

1. Summary: three to five sentences on what happened, the impact, the
   duration, the trigger and the current status.
2. Impact in numbers: users, requests, error rate, money, error budget, and
   the duration with a time zone.
3. Timeline: one event per line, in UTC and the past tense, each line linked
   to its evidence.
4. Causes: the trigger and the contributing conditions, described as systems
   and decisions.
5. Detection: how the incident was noticed, and how long that took.
6. Response and recovery: what was done, and how long mitigation took.
7. What went well, what went badly, and where the team was lucky.
8. Action items: an owner, a due date, whether each item prevents, detects or
   mitigates, and how to verify that it is done.
9. Open questions.

## Rules

- Keep it blameless: name systems, signals and decisions, not people
  (`no_filler`).
- Name the actor where it is known ("At 14:02 UTC deploy 812 changed the cache
  key format"), and say where it is not (`direct`).
- Keep the timeline factual and the analysis in its own section
  (`epistemic`).
- Never write "human error" as a cause or "be more careful" as an action.

Sources: STE 3.6; TW1 Audience and Documents. The section list is industry
practice, not from either source.
