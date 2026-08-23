---
name: doctor
description: Check git, jq, the remote, the head branch, the forge CLI and its permissions
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/origin *)
---

Check that everything the other commands need is in place.

```bash
${CLAUDE_PLUGIN_ROOT}/bin/origin doctor
```

Run this first when a command has failed for a reason that looks like setup —
an unauthenticated CLI, a remote nothing recognises, a head branch it cannot
resolve, a permission that is only read.

Each row is `ok`, `--` for a warning, or `no` for something that will stop a
command working. Every failing row carries the command that fixes it. Write
those commands out in your reply — the user does not see command output — and
do not run `gh auth login` or write git config on their behalf.
