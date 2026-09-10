---
name: rotate
description: Start the next branch in this chain, named after the one you are on
argument-hint: ""
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *)
---

In Codex, `$ARGUMENTS` means the arguments supplied with the skill. Substitute
them before running a command; do not read them from a shell variable.
Resolve `${CLAUDE_PLUGIN_ROOT}` to the plugin root, two directories above this
`SKILL.md`, if the client has not expanded it. Run the resulting absolute
script path from the repository being worked on.

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin rotate --yes
```

It takes no arguments. To choose the name yourself, use
`origin new-branch <name>` instead.

## On a work branch

Fetches, then creates `<branch>-YYYY-MM-DD_NNN` off the head branch and checks
it out. `feat-x` on the tenth gives `feat-x-2026-09-10_001`, and the next call
gives `_002`. A branch already carrying a suffix keeps one, so from
`feat-x-2026-09-10_001` the next is `feat-x-2026-09-10_002` rather than a second
suffix on top of the first. A name held here or on the remote is skipped.

The base is the head branch as the remote has it, so the new branch starts on
top of the server's copy and nothing has to be rebased afterwards. It tracks
nothing, so `git push` cannot land on the head branch.

Say which branch the session is now on. The old branch is left exactly where it
was.

## On the head branch

There is no chain to continue, so it fast-forwards the head branch to the
remote and says so. This is the same move `origin sync` makes there.

It refuses when this copy has commits the remote does not, listing them, because
a fast-forward would lose them. Relay that list. Those commits want a branch:
`origin new-branch <name>`.

## When it refuses

HEAD detached, exit 1. There is no branch to derive a name from, so
`origin new-branch <name>` is the way through.
