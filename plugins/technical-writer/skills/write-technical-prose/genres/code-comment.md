# Code comment and docstring

Reader: the next maintainer, about to change the code. They arrive asking why
the code is like this, and what they must not break.

## Rules

A comment takes one to three sentences and follows five rules:

- Comment what is not obvious. What is obvious to the author may not be
  obvious to a newcomer.
- For experienced readers, explain why rather than what.
- Keep text that must travel with copied code inside the comment.
- Keep a "why" only where the code looks wrong without it (`current_state`).
- When a sample trades production readiness for brevity, say so in the
  comment.

Sources: TW2 Creating sample code; practice.
