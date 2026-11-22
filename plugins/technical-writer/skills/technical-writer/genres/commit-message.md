# Commit message

Reader: a maintainer reading `git log` or `git blame`, and the release
tooling.

## Shape

A commit message has two parts:

1. A typed subject in the imperative, such as
   `fix(parser): reject an empty header`.
2. A body that says why, which alternatives lost, and any consequence that a
   later change must respect.

## Rules

- A commit message describes a change, not a state. It is the exception to
  `current_state`.
- Put the reason not to act in the body.
- Keep the subject under about 72 characters. The limit is practice, not a
  rule from the sources.

Sources: the [releasetools conventions](https://github.com/releasetools/conventions),
for the typed subject; practice.
