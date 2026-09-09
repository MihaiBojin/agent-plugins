# decisions

A decision that was not quick and easy gets a file, written while the work
happens rather than remembered afterwards. The file carries the question, the
answer, the reason argued, and each rejected option with what it would have
cost.

```markdown
q: Which git should we use: system, brew, user specified
a: use system git, cache the binary location for a day
why: brew git moves with the machine, system git does not
alt: git from $PATH on every call — 700ms of extra runtime
alt: a configured path — one more thing to set per machine
```

## The switch is a directory

`.claude/decisions/` at the repository root. It exists, the log is on; it does
not, nothing is ever written. A repository that has recorded something already
turns the log off with a `.disabled` file inside it, so opting out costs
nothing that was written.

| Command              | What it does                                                                  |
| -------------------- | ----------------------------------------------------------------------------- |
| `/decisions:enable`  | Creates the directory, drops any `.disabled`, says whether git will commit it |
| `/decisions:disable` | Writes `.disabled`, or removes the directory when it is empty                 |

Both run `bin/decisions`, which is also a CLI: `decisions enable`,
`decisions disable`, `decisions help`.

## Committing the log

`**/.claude/` is excluded on many machines, which would leave every decision
untracked. `enable` runs `git check-ignore` and prints the carve-out when the
path is ignored:

```gitignore
## Claude
!**/.claude/
**/.claude/*
!**/.claude/decisions/
```

Order matters. Git will not re-include a path whose parent directory is
excluded, so `.claude/` comes back before `.claude/decisions/` can. Those lines
live in the machine's own ignore file, not in the repository, so a second
machine needs them too.

## Install

```
/plugin marketplace add MihaiBojin/agent-plugins
/plugin install decisions@MihaiBojin
```
