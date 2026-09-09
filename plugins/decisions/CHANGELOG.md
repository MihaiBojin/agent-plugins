# decisions

Newest release first. Each says what changed, and the choices behind it.

## 0.1.0

The first release: a decision log a repository opts into, and the two commands
that move the switch.

- `.claude/decisions/` is the switch. Present means on, absent means off, and a
  `.disabled` file inside means off while every file already written stays.
- `/decisions:enable` creates the directory with a `.gitkeep`, clears any
  `.disabled`, and runs `git check-ignore` to say whether the log can be
  committed on this machine, printing the carve-out when it cannot.
- `/decisions:disable` writes the marker, or removes the directory when there
  is nothing in it. It deletes no decision file, ever.
- The skill carries the file format: one file per topic, `Topic:` and
  `Status:` lines, and `q:` / `a:` / `why:` / `alt:` entries appended under the
  date they were written.

### Choices

- The switch is a directory rather than a marker file. `.claude/.nodecisions`
  was the first shape considered and it cannot be committed: `**/.claude/*`
  excludes it on every machine carrying the usual carve-out, so the opt-out
  would vanish on the next clone and the log would come back on. A directory
  is already carved back out, and its absence is the safe default.
- `disable` never deletes a decision file. The alternative, removing the
  directory, makes turning a setting off destroy the record it was keeping.
- `enable` prints the ignore lines rather than writing them. The machine's
  ignore file is hand-maintained and shared with everything else on the
  machine, so a command run inside one repository does not edit it.
- The plugin ships no hook yet. A `Stop` hook that notices a decision made and
  not recorded is the enforcement this wants, and it needs the format to settle
  first.
