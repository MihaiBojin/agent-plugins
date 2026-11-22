---
name: audit-project-readme
description: >
  Use when the user asks to audit, fact-check or review a project README,
  check whether it is out of date, or find broken instructions, commands,
  links or badges.
---

# Audit a project README

Use the path the user supplied, or `README.md` in the working directory.
If the file is missing, report the exact path and stop. An audit leaves the
README and the rest of the checkout untouched.

Read the repository's instructions, contribution guide and writing conventions.
They take precedence over the guidance here. Mention a conflict in the report
when it affects a finding.

## Measure the file

Resolve the path to the README before changing directories. Run the checker
from the repository that contains the file. Set `checker` to the absolute path
of this plugin's [bin/readme](../../bin/readme) and `readme` to the absolute
path of the requested file. Use the same paths throughout.

```shell
bash "$checker" all "$readme"
```

Record the word, line and heading counts, maximum heading depth and fenced
blocks. Read the findings even when the checker exits successfully. It checks
outbound links, local workflow badges and inbound heading links. Check where
else this project documents itself, including a docs site, wiki, manual or
guide. Compare the README with projects that keep their documentation in
similar places. The [structure reference](../write-project-readme/references/structure.md)
has measured examples and section guidance.

## Verify the claims

Follow the [six factual checks](references/verify.md) for each applicable
claim. Compare a real artifact with the documented format, check commands and
flags, run the quickstart, check recommendations against current features, and
inspect link and badge results. Use a temporary working copy for examples that
write files. Compare what a new reader actually gets with what the README
promises. If a check cannot run, record the reason and leave the claim
unverified.

## Report

Group findings in this order, most consequential first within each group.
Give each finding a location and the evidence that produced it.

1. **Wrong.** Quote the claim and the command output, file contents or observed
   behavior that contradicts it.
2. **Broken.** Identify the link, badge or anchor and its failed target.
3. **Missing.** Identify a reader task the project supports and show where
   that support lives.
4. **Structure.** Use the measurements and documentation map to explain a
   problem with order, length or duplication.
5. **Prose.** Cite the applicable [writing rule](../write-technical-prose/SKILL.md)
   and the text it affects.

Report what passed when there are no findings. List any unverified claims
and finish with what a rewrite would change.
