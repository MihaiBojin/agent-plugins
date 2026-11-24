# Escalation and handoff

Reader: the person taking ownership of a problem or of work in progress.

Each shape below is an engineering adaptation of a protocol from healthcare or
the emergency services. None of them is the official form.

## SBAR: escalate a problem with a recommendation

An SBAR message has four fields:

1. Situation: the current problem and its impact.
2. Background: the relevant history and context.
3. Assessment: the evidence, its interpretation, and the uncertainty.
4. Recommendation: the specific action requested, its owner and its timing.

Keep observations apart from hypotheses (`epistemic`), and end with the
request.

## I-PASS: transfer work and responsibility

An I-PASS handoff has five fields:

1. Severity: the current risk, as stable, CAUTION or WARNING (`warnings`).
2. Summary: the current state, the impact, and the essential history.
3. Actions: open tasks, owners and deadlines.
4. Situational awareness: risks, warning signs, and if-then contingencies.
5. Synthesis by receiver: the receiver restates the priorities and accepts
   ownership.

Sending the handoff is not acceptance. On a consequential transfer, confirm
ownership.

## CUS: stop unsafe work

A CUS message has three fields:

1. Concerned: state the concern.
2. Uncomfortable: explain why the current course is unsafe.
3. Safety issue: name the hazard and the stop or escalation required.

Use CUS only for a WARNING-level risk that needs an explicit stop or
escalation, never as a general severity label.

Sources: the situations in the dialogue plugin.
