# decisions

Newest release first. Each says what changed, and the choices behind it.

## 0.2.0 - 2026-10-10

Use the decision-interview skill for guided planning one question at a time. It tracks outstanding questions, updates the requested design records as answers arrive, and prepares a review handoff with unresolved and discarded choices. An explicit review gate keeps implementation paused until the user proceeds.

### Choices

The interview is a separate skill within decisions so it can be requested for
planning without turning ordinary work into a questionnaire. It preserves the
existing opt-in log and links qualifying decisions rather than duplicating
their reasoning. Question IDs stay stable when the queue shrinks; unresolved
and discarded items remain distinct at review.

## 0.1.1

The install command in the README reads `decisions@mihaibojin`. The
marketplace is named `mihaibojin`, so that is the handle to type after `@`.

## 0.1.0

The first release: a decision log a repository opts into, and the commands and
hook around it.

- `.decisions/` at the repository root is the switch. Present means on, absent
  means off, and a `.disabled` file inside means off while every file already
  written stays.
- `/decisions:enable` creates the directory with a `.gitkeep`, clears any
  `.disabled`, and runs `git check-ignore` to say whether the log can be
  committed here.
- `/decisions:disable` writes the marker, or removes the directory when there
  is nothing in it. It deletes no decision file, ever.
- A `Stop` hook says once per session when the log is on, the session ran
  longer than a turn, and nothing reached `.decisions/`.
- The skill carries the file format: one file per topic, `Topic:` and
  `Status:` lines, and `q:` / `a:` / `why:` / `alt:` entries appended under the
  date they were written.

### Choices

- The log is `.decisions/` at the repository root, not `.claude/decisions/`.
  The record is the repository's, not one agent's, and a path under `.claude/`
  reads as Claude's private state to everyone else working there. It also drops
  the `~/.config/git/ignore` carve-out the `.claude/` path needed: a root
  directory is committable everywhere with no per-machine setup.
- The switch is a directory rather than a marker file. `.claude/.nodecisions`
  was the first shape considered and could not be committed at all under the
  usual `**/.claude/*` exclusion, so the opt-out would vanish on the next clone
  and the log would come back on.
- `disable` never deletes a decision file. The alternative, removing the
  directory, makes turning a setting off destroy the record it was keeping.
- The hook checks three mechanical facts and judges nothing. A hook that tried
  to decide what was significant would either ask a model on every stop or
  match on words, and the first costs a call per turn while the second fires on
  prose about deciding.
- It blocks the stop rather than printing quietly, once per session. A message
  nothing waits for is a message read after the session it was about.
