# Why origin ships as a plugin

Topic: origin is a shell CLI, and the reason it also ships as an agent plugin keeps coming back
Status: decided 2026-09-07
Opened: 2026-09-07

## 2026-09-07

q: How does origin reach an agent: a plugin, a script on PATH, or loose slash commands?
a: a plugin, carrying the skill, the commands and the CLI as one versioned unit
why: the skill is the only thing that makes a model run bin/origin rather than compose git itself, and the refusals in lib/common.sh bind nothing the model does not run through
alt: install.sh alone — a binary on PATH announces itself to a shell, not to a model
alt: loose ~/.claude/commands/*.md — no version, no update path, and Codex sees none of it
