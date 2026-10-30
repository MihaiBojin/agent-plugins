---
name: dialogue
argument-hint: "[help | enable | disable | settings | set <setting> <value> | defaults show | defaults set <setting> <value>]"
description: Use only when the user explicitly invokes dialogue to enable, disable, inspect, or configure conversation behavior. Never activate from ordinary discussion of threads, focus, or writing style.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

# Dialogue

This command controls persistent conversation settings. Installing it does not enable it.
Do not apply response or thread instructions merely because this file was read. Apply only the policy returned by the tool for the current session.

## Run the requested command

For `help`, `--help`, or `-h`, show the command table below and the accepted settings and values. Explain that no arguments enables this session, `set` changes only this session, and `defaults set` affects future sessions. Do not run a state-changing command or enable dialogue when showing help. Help does not require a session ID.

The tool is `../../bin/dialogue` relative to this skill directory. Resolve its absolute path from this file's location.
In Claude, the plugin root is `${CLAUDE_PLUGIN_ROOT}` and the session ID is `${CLAUDE_SESSION_ID}`.
In Codex, use the loaded skill's absolute location and the `CODEX_THREAD_ID` environment variable.
Pass `--client claude` or `--client codex`. Use the actual current session ID with `--session` when supplied by the client.
Never substitute the working directory, a transcript filename, a guessed ID, or another session's ID.
If the client does not expose an ID, stop and report that session isolation cannot be established.

Treat the user's arguments as data. Pass them as separately quoted arguments; never eval them or interpolate them into shell code.
Claude supplies `$ARGUMENTS`. Codex supplies the arguments in the user's invocation.
No arguments means `enable`. A request to inspect settings means `settings`, which never enables the plugin.
Natural-language requests to stop dialogue or return to normal mode mean `disable` once this plugin is active.

| Arguments                  | Effect                                                                 |
| -------------------------- | ---------------------------------------------------------------------- |
| `help`                     | Show subcommands, settings, and accepted values without changing state |
| `enable`                   | Enable this session and apply the returned policy                      |
| `disable`                  | Disable this session, retain its records, and stop applying its policy |
| `settings`                 | Print the complete table of session values, defaults, and explanations |
| `set focus on`             | Save one session setting and apply the returned policy                 |
| `set compact off`          | Expand the displayed backlog without changing work order               |
| `set threads off`          | Suspend thread tracking while retaining its records                    |
| `set response_style plain` | Stop applying the plugin's response style                              |
| `defaults show`            | Show current values and the defaults for new sessions                  |
| `defaults set enabled on`  | Explicitly opt future sessions into automatic startup activation       |
| `defaults set enabled off` | Keep future sessions off until explicitly invoked                      |

`set enabled on/off` is equivalent to enabling/disabling. Other settings never implicitly enable the plugin.
The setting names are `enabled`, `threads`, `focus`, `compact`, and `response_style`. Both `set <setting> <value>` and `defaults set <setting> <value>` accept these names.
All settings accept `on/off` or `true/false` except `response_style`, which accepts `pyramid/plain`.
Defaults affect only sessions that have not yet saved a snapshot. Existing sessions keep their values.
A session's explicit off remains off after restart, resume, and compaction, even when defaults enable new sessions.
The hook restores saved policy; the model must never invent a reason to turn it on.

After enabling or changing settings, follow the tool's returned policy. The shared rule sources are [threads.md](threads.md) and [response.md](response.md); the tool selects the applicable parts.
When thread tracking is enabled, persist each transition with the tool. Run `thread --help` and its subcommand help for syntax.
Use `state` to inspect the complete saved record, `render` to reload the effective instructions, and `thread list --details` for a full audit.
When disabled, inspection remains available but thread mutations are refused.

## Agent-rules migration

Before using this alongside agent-rules, use its `make install-limited` target and `make project-limited DIR=...` for any project-level installs, then start a fresh session.
Those targets keep engineering guidance but omit overlapping conversation rules. Check `make status` for mixed scopes.
Do not run installation or alter the user's global defaults as a side effect of enabling this session.
For rollback, disable dialogue and restore the full agent-rules profile with `make install` and any applicable `make project DIR=...`, then start a fresh session.

## Failure handling

Python 3.9 or newer is required; there are no third-party Python packages. Never install a runtime or package automatically.
Report a missing interpreter or corrupt state. Do not pretend a setting or thread was saved after a failed command.
The state directory is outside the plugin cache, so plugin updates do not erase it. Do not manually edit or delete state to bypass an error.
