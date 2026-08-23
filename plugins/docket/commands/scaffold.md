---
name: scaffold
description: Turn a directory of the current repo into a docket collection
argument-hint: "<collection> [rfc|decision] [notion|gdocs|git]"
allowed-tools:
  - Bash(cp ${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs .github/scripts/docket.mjs)
  - Bash(cp "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs" .github/scripts/docket.mjs)
  - Bash(cp ${CLAUDE_PLUGIN_ROOT}/skills/docket/docket-ci.yml .github/workflows/docket-ci.yml)
  - Bash(cp "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket-ci.yml" .github/workflows/docket-ci.yml)
  - Bash(mkdir -p .github/scripts .github/workflows)
---

`$ARGUMENTS` is the collection directory, then optionally the profile and the
backend. Ask for whichever of the two is missing - profile `rfc` or
`decision`, backend `notion`, `gdocs` or `git` - rather than defaulting.

Then, from the archive repo's root, three writes and nothing else:

1. Create `<collection>/docket.toml`:

   ```toml
   profile = "<profile>"
   backend = "<backend>"
   width = 4
   ```

2. Copy the check into the repo, so CI never depends on this plugin being
   installed:

   ```bash
   mkdir -p .github/scripts .github/workflows
   cp "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs" .github/scripts/docket.mjs
   cp "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket-ci.yml" .github/workflows/docket-ci.yml
   ```

Say what was written and that the workflow will enforce immutability on every
pull request once committed. Commit only if the user asks. If the directory
is already a collection, or the workflow file already exists, say so and
change nothing.
