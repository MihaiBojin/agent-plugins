---
name: write-project-readme
description: >
  Use when the user asks to write or create a project README, or to update,
  correct, shorten, restructure or rewrite an existing one.
---

# Write a project README

Use the path the user supplied, or `README.md` in the working directory.
Read the repository's instructions and writing conventions first.

## Establish what the project does

- **Existing README.** Run [audit-project-readme](../audit-project-readme/SKILL.md)
  on the chosen path and show the findings before editing. Keep the original
  measurements for comparison.
- **New README.** Inspect the project and its existing documentation. Use
  the audit's [factual checks](../audit-project-readme/references/verify.md)
  to gather evidence for the claims you plan to make. Run the proposed
  commands and check their results in a temporary working copy. The checks
  that read a README begin once the draft exists.

## Write in place

Correct factual errors first. Use the [README structure](references/structure.md)
to choose the content and order. Apply the shared rules, document rules and
`self_edit` from [write-technical-prose](../write-technical-prose/SKILL.md)
to the sentences. Write examples that readers can run and give the observed
result.

Before removing or renaming a heading, find what points to it. Use the audit's
anchor check and search the repository for the target filename, heading and
topic. Look for prose such as “the exit codes are documented in README.md”
as well as Markdown links. When replacing material with a link, read the
destination and confirm it covers the details readers need. Repair affected
incoming links and prose references as part of the edit.

## Verify the draft

Read the [humanizer patterns](references/humanizer.md) when editing your own
prose. Check for staged contrasts, one-line closers, forced groups of three,
overused dashes and decorative bold. Keep this skill's workflow.
Run [audit-project-readme](../audit-project-readme/SKILL.md) against the
finished file, including the quickstart and examples added during the rewrite.
Fix issues the new draft introduced and rerun the affected checks. Report
before-and-after measurements for a rewrite, or the draft measurements for a
new file. Give the final audit results even when it finds nothing, and identify
any claim you could not verify.
