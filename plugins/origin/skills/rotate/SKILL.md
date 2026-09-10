---
name: rotate
description: Print the name the next branch would take, derived from the branch you are on
argument-hint: ""
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *)
---

In Codex, `$ARGUMENTS` means the arguments supplied with the skill. Substitute
them before running a command; do not read them from a shell variable.
Resolve `${CLAUDE_PLUGIN_ROOT}` to the plugin root, two directories above this
`SKILL.md`, if the client has not expanded it. Run the resulting absolute
script path from the repository being worked on.

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin rotate
```

One name on stdout and nothing else, so it reads straight into a variable. It
changes nothing: no branch is created, no ref is written, and running it twice
gives the same answer.

## What the name means

`<branch>-YYYY-MM-DD_NNN`, from the branch checked out now. `feat-x` on the
tenth gives `feat-x-2026-09-10_001`, and once that exists the next call gives
`_002`. A branch already carrying a suffix keeps one: from
`feat-x-2026-09-10_001` the next name is `feat-x-2026-09-10_002`, not a second
suffix on top of the first.

A name already taken here or on the remote is skipped, so two clones working
the same day do not choose the same one.

## When it refuses

Two cases, both exit 1 with the reason on stderr:

- The head branch is checked out. A branch off `main` is new work rather than
  the next step in a chain, so it needs a name somebody chose. Relay that and
  ask for one.
- HEAD is detached. There is no branch to derive from.

## Where it is already called

`origin new-branch` with no name calls this itself, so
`origin new-branch` and `origin new-branch "$(origin rotate)"` do the same
thing. Reach for `rotate` on its own when the user wants to see the name before
the branch exists, or when something other than `new-branch` needs it.
