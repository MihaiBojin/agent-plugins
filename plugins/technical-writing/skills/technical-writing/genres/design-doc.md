# Design doc and RFC

Reader: reviewers deciding whether to approve, then implementers and future
maintainers. They arrive asking what the problem is, what is proposed, what it
costs, and what is wanted from them.

When the
[docket plugin](https://github.com/MihaiBojin/agent-plugins/tree/main/plugins/docket#readme)
is installed, it handles the lifecycle: draft, discussion, final comment
period and freeze, with surviving dissent written into the frozen document.
This file supplies the body.

## Shape

A design doc has nine sections:

1. Summary: the problem, the proposal and the ask, so that a reader who stops
   here can still respond.
2. Audience and prerequisites, including required reading.
3. Context: what the reader needs minus what they know, with links instead of
   retelling.
4. Goals and non-goals. A non-goal is only something that a reader would
   reasonably expect the document to cover.
5. Proposal: the big picture first, then each subsystem. Write the caption of
   each diagram before you draw it.
6. Alternatives considered, each with the reason it lost.
7. Risks, trade-offs and costs, in numbers where there are numbers.
8. Rollout, migration and testing.
9. Open questions and recorded dissent.

## Rules

- Use the scope statement to cut sections that do not serve it.
- Compare the design with a system that the readers know.
- Use headings that a reviewer would ask as questions, and put text under
  every heading.
- Write an outline first, and share it before you draft.
- Keep each diagram to what one paragraph could explain. Label every shape,
  and never encode a category by color alone (`no_visual_only`).
- The alt text of a diagram states the takeaway, and the body walks through
  each part (`navigable`).
- Write the first draft yourself. Google's unit on LLMs warns that a generated
  draft skips the thinking: "One writes to know what one is thinking."

Sources: TW1 Documents; TW2 Organizing large documents, Illustrating, and
Using LLMs. The section names are practice.
