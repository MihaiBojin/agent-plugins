---
name: set
description: Change one dialogue setting for this session
argument-hint: "<key> <value>"
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
  - Bash("${CLAUDE_PLUGIN_ROOT}/bin/dialogue" *)
---

`$ARGUMENTS` is the key and the value. Pass each as its own quoted argument;
never eval them or splice them into shell code.

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/dialogue" --client claude --session "${CLAUDE_SESSION_ID}" set "KEY" "VALUE"
```

In Codex, pass `--client codex` and omit `--session`: the tool reads
`CODEX_THREAD_ID`.

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

`communication_profile`, `language_standard` and `signaling` are the full names
of `comms`, `style` and `signals`. Booleans also take `true` and `false`.
`/dialogue:dialogue guideline` changes one guideline; `set` does not.

Only `set enabled on` enables dialogue. When the tool returns a policy, follow
it from the next reply. If the command fails, report the error and do not claim
the setting was saved.
