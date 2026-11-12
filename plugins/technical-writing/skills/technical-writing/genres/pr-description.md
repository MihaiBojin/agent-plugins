# PR description

Reader: the reviewer deciding whether to approve, and later whoever finds the
merge commit. They arrive asking what the change does, how to verify it, and
what could break.

## Shape

A description has five parts, on one screen:

1. What the code does now, in one paragraph.
2. Why, only where the code would look wrong without it.
3. How it was verified, with the commands and their results.
4. Risk and rollout.
5. The release note, when the repository asks for one.

## Rules

- Describe the change, not the list of commits.
- Describe the new state, for a reader who never saw the old one
  (`current_state`).
- The alt text of a screenshot says what the reviewer should notice
  (`navigable`).

Sources: practice.
