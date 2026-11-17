---
name: help
description: What dialogue can do: its commands, settings and accepted values
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory, with `--client codex`. It needs no session ID. In the commands below, `dialogue` stands for that whole prefix.

```bash
dialogue help
```

Show the complete output. Then list the commands, as `/dialogue:NAME` in Claude Code and `$dialogue:NAME` in Codex:

- `enable` and `disable` turn dialogue on and off for this session.
- `setup` asks three questions and saves the answers.
- `settings` shows every setting, its session value and its default; `state` prints the saved record as JSON.
- `set <key> <value>` changes one setting for this session.
- `defaults show` and `defaults set <key> <value>` read and change the defaults for future sessions.
- `profiles`, `languages`, `signals` and `situations` list the options for `comms`, `style`, `signals` and `situation`.
- `guidelines` lists the rules; `guideline` overrides one rule or one group.
- `situation preview|use|clear` inspects or applies a situational framework.

This is read-only: it writes nothing and does not enable dialogue.
