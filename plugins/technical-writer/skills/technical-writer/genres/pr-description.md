# PR description

Reader: the reviewer deciding whether to approve, and later whoever finds the
merge commit. The reviewer arrives asking what the change does, why, how it
was checked, and what could break. The later reader has the commit and
nothing else.

The `pr-description` skill of this plugin collects the facts and hands the
writing to an agent that reads the diff. This file is the format both follow.

## Shape

The title says what the change does, in the imperative and with the prefix
that the repository's history uses: "Add a retry budget per destination
host". It has at most 72 characters and no full stop.

The body has six parts, in this order:

1. What the code does after the merge: one paragraph in the present tense,
   with no heading above it. A reader who stops here knows the change.
2. Why: the problem and its impact, in one or two sentences, with the numbers
   that exist and the issue that the change closes.
3. `## Review guide`, for a diff too large to read in one sitting: where to
   start, which parts are mechanical, and what feedback the author wants.
4. `## Verification`: each command that ran, with its result. Then each check
   that a reviewer would expect and that did not run, with the reason, on a
   line that starts "Not verified:".
5. `## Risk`: what can break, whom it affects, and how to turn the change off
   or roll it back.
6. What the repository or its tools put in a description: a template
   section, a `release-note` block, an issue keyword, a footer. Keep each one
   exactly as written.

Parts 1 and 4 are in every description. Each other part appears when it has
something to say, and an empty heading never does. A one-line fix takes
part 1 and part 4. One screen is the limit.

## Rules

- Every sentence says one of five things: what the code does, what problem
  that solves, how to read the diff, what shows that it works, or what can
  go wrong. How the work went is none of the five: the attempts that were
  dropped, the order of the commits, the review rounds (`current_state`).
- State a removal as a fact about the code: "The fixed retry count is
  removed." An alternative that a reviewer would ask about takes one sentence
  in the present tense: "Backoff alone still retries an endpoint that is
  down."
- Each line names a behavior, an interface or a decision. A file and a commit
  are neither: three commits that fix one bug are one sentence.
- Every claim matches the diff. Name each change that a reader of the diff
  would notice: a new or renamed flag, command, default, file format or
  dependency, and each behavior that the diff removes. Claim nothing that the
  diff does not do.
- A reason, a number or a test result comes from the diff, the commits, the
  linked issue or the author. When none of them gives it, say that it is not
  known (`epistemic`).
- Verification names what ran: the command and what it printed, not "tested
  locally".
- The alt text of a screenshot says what the reviewer should notice
  (`navigable`).

## What makes a description wrong

Check each line against the diff:

1. A line claims a change that the diff does not make, or no longer makes
   after later commits.
2. The diff makes a change that a reader would notice and no line names it.
3. The title describes a different or a smaller change than the diff.
4. A line breaks a rule above, or a rule of the repository.

A description with none of the four is right. Leave a correct line as its
author wrote it.

Sources: Google Engineering Practices,
[Writing good CL descriptions](https://google.github.io/eng-practices/review/developer/cl-descriptions.html);
the Linux kernel's
[Submitting patches](https://docs.kernel.org/process/submitting-patches.html),
Describe your changes; GitHub Docs,
[Helping others review your changes](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/getting-started/helping-others-review-your-changes).
Two studies set the priorities. Bian and Zhang (2026) found that 28.3% of
agent-written pull requests whose description did not match the code were
accepted, against 80.0% of the others ([arXiv 2601.04886](https://arxiv.org/abs/2601.04886)).
Pirouzkhah, Wurzel Gonçalves and Bacchelli (2026) surveyed 57 developers, who
valued the purpose, the reason and the linked issue most
([arXiv 2602.14611](https://arxiv.org/abs/2602.14611)). The order of the
parts is practice.
