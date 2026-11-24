# decisions

Newest release first. Each says what changed, and the choices behind it.

## 0.3.2 - 2026-11-24

The README points a record that a team approves, and that nobody may edit
afterward, to the docket plugin's `decision` profile.

## 0.3.1 - 2026-11-22

The decisions Stop hook runs when the plugin's installation path contains spaces.

### Choices

The quoted command string works with both the CI-pinned and current Claude Code versions.

## 0.3.0 - 2026-11-15

An agent that goes against a request because the docs or research show it cannot work, or that it is deprecated, wrong or non-idiomatic, picks the best approach without asking. The decisions skill records each such case, with the request as an `alt:` and the source in `why:`. The decision-interview skill stops queueing questions that only confirm such a request, and asks only when the goal itself is unknown.

### Choices

Recording the case takes the place of asking for confirmation: the user can read why a request was not followed without being asked first. It matches the judgment rule in agent-rules.

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
