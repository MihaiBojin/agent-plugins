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

This project needs its first README. Give a new user a quickstart that counts
warnings in the included sample and shows the expected output. Return the
README in Markdown here. After the draft, add a short verification note
explaining how you checked it. The project snapshot is read-only.
