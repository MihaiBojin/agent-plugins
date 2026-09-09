# decisions

A decision that stayed open across turns, and that changes what somebody would
do later, gets a file: the question, the answer, the reason argued, and each
rejected option with what it would have cost. Written while the work happens
rather than remembered afterwards.

```markdown
q: Which git should we use: system, brew, user specified
a: use system git, cache the binary location for a day
why: brew git moves with the machine, system git does not
alt: git from $PATH on every call — 700ms of extra runtime
alt: a configured path — one more thing to set per machine
```

## The switch is a directory

`.decisions/` at the repository root. It exists, the log is on; it does not,
nothing is ever written. A repository that has recorded something already turns
the log off with a `.disabled` file inside it, so opting out costs nothing that
was written.

| Command              | What it does                                                                  |
| -------------------- | ----------------------------------------------------------------------------- |
| `/decisions:enable`  | Creates the directory, drops any `.disabled`, says whether git will commit it |
| `/decisions:disable` | Writes `.disabled`, or removes the directory when it is empty                 |

Both run `bin/decisions`, which is also a CLI: `decisions enable`,
`decisions disable`, `decisions help`.

## The reminder at the end

A `Stop` hook fires once per session, and only when three things are true at
the same time: the log is on here, the session ran longer than a single turn,
and nothing reached `.decisions/`. Whether anything in the session earned a
file is the judgement it hands back to the agent, which answers by writing one
or by saying in a line why nothing qualifies.

## Where the log lives

`.decisions/` sits at the repository root rather than inside `.claude/`,
because the record belongs to the repository rather than to one agent. It needs
no ignore rules to be committable. `enable` runs `git check-ignore` anyway and
says so when a repository excludes it, since a log nothing can commit looks
exactly like a log nobody wrote.

## Install

```
/plugin marketplace add MihaiBojin/agent-plugins
/plugin install decisions@MihaiBojin
```
