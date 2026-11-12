# Decision record

Reader: a future engineer asking why the system is the way it is.

When the docket plugin is installed, its `decision` profile handles the
lifecycle. This file supplies the body.

## Shape

A record has six parts:

1. The decision, as the title.
2. Status.
3. Context: the forces and constraints, with numbers.
4. The decision, in one active sentence.
5. Consequences, good and bad.
6. Alternatives, with one line each on why they lost.

## Rules

- Write one decision per record.
- Use the present tense for the decision.
- Record the reason not to act. What a later change needs, and cannot get from
  the diff, is the alternative weighed and dropped, the cost taken on purpose,
  or the bug left alone because something else already stops it.

Sources: practice, for the context, decision and consequences shape.
