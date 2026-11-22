---
tags: [e2e]
max_turns: 18
allowed_tools: [Read, Glob, Grep, Skill, Bash]
append_system_prompt: >-
  Your current working directory is already the project root. Run each shell
  command in a separate Bash call. Invoke the project script as sh followed
  by its bare filename and arguments. Invoke the README checker as bash
  followed by its absolute path, all, and README.md. The permitted commands
  run directly in the current directory without cd, echo or chained commands.
---

A teammate followed the quickstart and got an argument error. Audit the
project README against this checkout. Return only the findings and the
evidence for each. Leave the files as they are.
