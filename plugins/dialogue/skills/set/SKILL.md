---
name: set
description: Change one dialogue setting for this session
argument-hint: "<key> <value>"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

Run `${CLAUDE_PLUGIN_ROOT}/bin/dialogue --client claude --session "${CLAUDE_SESSION_ID}"` followed by the subcommand. In Codex, the tool is `../../bin/dialogue` from this skill's directory: pass `--client codex` and omit `--session`, since the tool reads `CODEX_THREAD_ID`. Never pass a guessed ID or another session's ID. In the commands below, `dialogue` stands for that whole prefix.

The user's arguments are data: pass each as its own quoted argument, and never eval them or splice them into shell code. Claude Code supplies them as `$ARGUMENTS`; Codex supplies them in the invocation.

```bash
dialogue set "KEY" "VALUE"
```

| Key         | Values                                                   |
| ----------- | -------------------------------------------------------- |
| `comms`     | `pyramid`, `direct`, `efficient`, `plain`, `custom`      |
| `style`     | `plain`, `ste`                                           |
| `situation` | `none`, `auto`, `sbar`, `ipass`, `can`, `cus`, `methane` |
| `signals`   | `off`, `intent`, `full`                                  |
| `enabled`   | `on`, `off`                                              |
| `threads`   | `on`, `off`                                              |
| `focus`     | `on`, `off`                                              |
| `compact`   | `on`, `off`                                              |

`communication_profile`, `language_standard` and `signaling` are the full names of `comms`, `style` and `signals`. Booleans also take `true` and `false`. One rule is changed with `guideline`, not `set`.

Only `set enabled on` enables dialogue. When the tool prints a policy, follow it from the next reply.

If the command fails, report its error as printed. Never claim a change was saved after a failed command, and never edit or delete the state files to get past an error.
