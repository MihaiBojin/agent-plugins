# Incident update

Reader: stakeholders or customers while the incident is live. They arrive
asking whether it is still happening, whether it affects them, what is being
done, and when they will hear more.

## Shape

An update has four parts, in under 100 words:

1. Conditions: the current state and the impact.
2. Actions: what is being done, and by whom.
3. Needs: the decision, help or resources required, or "none".
4. Next update by HH:MM UTC.

The first report on a major incident uses an engineering adaptation of
M/ETHANE, a major-incident report from the emergency services. It is not the
official form. Its seven fields are:

1. Major incident: declared or suspected, with WARNING or CAUTION
   (`warnings`).
2. Exact location: the affected system, region or location.
3. Type: the incident category.
4. Hazards: known or suspected risks.
5. Access: access constraints, dependencies, or the safe path to intervene.
6. Number affected: the scope and the impact.
7. Emergency response: the teams involved and the help required.

## Rules

- The material change leads (`bluf`).
- Use the present tense for the current state.
- An external update does not speculate about the cause (`epistemic`).
- Use the same incident name in every update (`terminology`).
- Give the impact in numbers (`quantify`).

Sources: the CAN and M/ETHANE situations in the dialogue plugin; practice,
for the next-update line.
