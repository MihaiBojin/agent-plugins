---
name: decision-interview
description: Guide a substantial design or planning task through one material question at a time, maintain decisions and open questions on disk, simplify scope, and prepare a reviewable handoff. Use when the user asks for an incremental interview, guided requirements discussion, or documented design choices; do not impose an interview on straightforward implementation work.
---

# Decision Interview

Turn the user's intent into a concise, reviewable design through a small number of consequential decisions. The conversation is incremental; the documents remain coherent as answers arrive. Use the user's preferred name when established, without embedding a particular person's identity in this reusable skill.

## Establish the working agreement

Read existing project guidance, current plans and decisions before asking anything. Recover previous answers and outstanding work instead of restarting the interview. Carry forward explicit constraints, authorization and later corrections.

For a new substantial design, preserve the initial task request unchanged when writing the requested planning package. Use the existing repository/document conventions; otherwise use a short overview, topic-focused design files, a decision record and a single open-question file. Scale the package to the project rather than generating a file per trivial choice. Ask about a missing destination only if it cannot be inferred safely.

Capture an explicit user-review gate when requested. Planning permission permits research and document updates, not implementation across that gate. Do not invent an approval gate when none was requested. Commit, publish, install or message other people only within the actual task authorization; this skill grants none of those permissions by itself.

### Work with the existing decision log

This skill adds an interview, not a second automatic logging policy. Read [the decisions skill](../decisions/SKILL.md) before using `.decisions/`; honor its directory switch, disabled marker, qualification rules and record format. Do not enable it implicitly. When the user requests a saved planning package, keep the question queue and current design there. Record qualifying choices in the enabled decision log and link to them rather than duplicating the reasoning. If logging is off, use only the planning records the user requested. Keep session state in the conversation when no disk output was requested.

## Ask one material question

Before adding a question, check whether its answer is already recorded, follows from a chosen constraint, or can be handled as ordinary implementation judgment. Ask about consequential product behavior, trust boundaries, scope, external dependencies and real tradeoffs. Do not ask the user to design every internal mechanism, test case or tuning value.

Present one question with two or three concrete options when useful. Explain the practical difference in plain language, recommend an option only when justified, and allow a free-form answer. Avoid bundled unrelated choices. Never include a hidden second question in the introduction or closing sentence.

Show the stable question number and remaining count, without zero padding. Calculate both from the maintained queue (saved when disk output is authorized) immediately before presenting the question; do not count from memory. For a numbered interview, use `7/14 — 8 questions remain`, where 14 is the allocated total and unresolved deferred entries are included in the remaining count. Explain any skip caused by a conditional closure, deferral or simplification. Renumber only on an explicit request, with an old-to-new mapping.

Keep recommendations distinct from accepted decisions. If the user asks what an option means, answer the explanation first, with concrete examples or researched tradeoffs as needed. The explanation does not select that option or advance the counter.

## Interpret and persist each reply

- A numeric reply selects an option from the current clearly identified question only. Record the option's meaning, not just the digit.
- A refinement can amend an earlier decision while leaving the current question pending. Apply it to the correct topic.
- “Next” without an answer defers the question; it is not approval of the recommendation. Keep genuinely unresolved work visible.
- “Choose during implementation” closes that interview decision as delegated work. Record the qualification criteria instead of pretending a technology has been selected.
- If an answer eliminates a conditional topic, mark it not applicable and remove its queued ask. Distinguish this from a skipped question.
- If an answer provides only public information but a workflow requires private authority or material, record the remaining dependency explicitly; do not silently infer it. Avoid re-asking immediately if the user deliberately deferred it.

After each material answer, update the authorized decision record, affected design sections, and open-question queue before asking the next question. If working only in conversation, maintain the same state there. Record source/meaning, consequences and superseded decisions. Remove solved asks from the open-question file; retain their history in the decision record. Rewrite current guidance that contradicts the new decision instead of merely appending another note.

Keep the user's original request intact. Do not copy private session details or unrelated attachments into reusable assets or published design documents.

## Research without turning it into another interview

Investigate technical uncertainty through available code/docs, maintained primary sources and focused experiments when authorized. Distinguish published capability, engineering inference, proposed design and measured evidence. Do not claim that a candidate library, generated chart or synthetic workload proves the final system's performance.

Offer a grounded recommendation and record meaningful tradeoffs. Keep engine selection, numeric limits and performance qualification as implementation tasks when the user delegates them. A deferred benchmark must not become a made-up production guarantee or another sequence of tuning questions.

## Simplify deliberately

When the queue grows, or the user asks to avoid overcomplication, review every remaining item. Classify it as:

- A material user choice that remains open.
- Resolved by an existing decision.
- A simple initial default applied under the user's delegated judgment.
- Merged into another question.
- Outside initial scope or conditionally not applicable.
- Implementation/benchmark work rather than an interview question.

Preserve the reason and any real dependency. Do not call an applied default an explicit user selection. Do not drop security or correctness work merely to reduce the count. Prefer the fewest components that meet accepted requirements, without layering on speculative services, extensive configuration knobs or new approval workflows.

After pruning, report the new remaining count and which kinds of questions moved out. Keep stable IDs even when the next displayed number jumps. Detailed dispositions belong in the review record, not a long repeated conversational checklist.

## Close with a reviewable handoff

The active interview can finish with explicitly agreed deferrals. State those separately from completed decisions. Provide one review entry point listing:

1. Current design and accepted choices.
2. Unanswered/deferred questions and what they block.
3. Discarded, merged and delegated questions with reasons.
4. Engineering defaults and proposals that are not final selections.
5. The next steps after review, including any requested checkpoint/branch workflow.

If the user requested a clean planning commit, validate the document links, queue and original-request preservation, inspect exactly what will be committed, and commit the planning state without unrelated files or secrets. Respect configured signing; do not silently disable it to make a commit succeed. Verify the resulting working-tree state. Push only to an authorized destination and verify remote refs before claiming publication.

If review is required, stop there: preparing a feature branch is not permission to implement. Resume only after the user asks to proceed, incorporate review changes first, and use a requested feature stack with traceable parent/base commits. Do not prescribe Git or stacked branches for projects that did not request them.

## Supporting references

- Read [decision-state.md](references/decision-state.md) when initializing or repairing the persisted queue, counts or decision history. It contains the minimal state conventions and examples.
- [agent-rules.md](references/agent-rules.md) is a compact opt-in rules snippet for users who want this interaction preference in an existing agent-rules file. Do not install global rules or alter unrelated preferences automatically.
