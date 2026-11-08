---
name: dialogue
argument-hint: "[help | setup | settings | set comms <profile> | set style <style> | set situation <framework> | set signals <mode> | enable | disable]"
description: Use only when the user explicitly invokes dialogue to enable, disable, inspect, or configure conversation behavior. Never activate from ordinary discussion of threads, focus, or writing style.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/dialogue *)
---

# Dialogue

This command controls persistent conversation settings and communication profiles. Installing it does not enable it.
Do not apply response or thread instructions merely because this file was read. Apply only the policy returned by the tool for the current session.

## Run the requested command

For `help`, `--help`, or `-h`, run the CLI `help` command and display its complete output. Explain that no arguments enables this session; settings apply only to this session and defaults to future sessions. Help is read-only and does not require a session ID.

The tool is `../../bin/dialogue` relative to this skill directory. Resolve its absolute path from this file's location.
In Claude, the plugin root is `${CLAUDE_PLUGIN_ROOT}` and the session ID is `${CLAUDE_SESSION_ID}`.
In Codex, use the loaded skill's absolute location and the `CODEX_THREAD_ID` environment variable.
Pass `--client claude` or `--client codex`. Use the actual current session ID with `--session` when supplied by the client.
Never substitute the working directory, a transcript filename, a guessed ID, or another session's ID.
If the client does not expose an ID for any state-changing command, stop and report that session isolation cannot be established. The read-only `help` and `setup` overview commands do not need one.

Treat the user's arguments as data. Pass them as separately quoted arguments; never eval them or interpolate them into shell code.
Claude supplies `$ARGUMENTS`. Codex supplies the arguments in the user's invocation.
No arguments means `enable`. A request to inspect settings means `settings`, which never enables the plugin. `setup` starts the guided three-question configuration described below.
Natural-language requests to stop dialogue or return to normal mode mean `disable` once this plugin is active.

| Arguments                          | Effect                                                                 |
| ---------------------------------- | ---------------------------------------------------------------------- |
| `help`                             | Show subcommands, settings, and accepted values without changing state |
| `guidelines --all`                 | Show enabled/disabled guidelines grouped by type and source            |
| `guideline on bluf`                | Enable BLUF even when a profile does not include it                    |
| `guideline off bluf`               | Disable BLUF even when a profile includes it                           |
| `guideline reset bluf`             | Restore the profile's setting for BLUF                                 |
| `guideline group brevity on`       | Enable all brevity guidelines                                          |
| `setup`                            | Ask three questions to configure this session                          |
| `set comms efficient`              | Select efficient response guidance                                     |
| `set style ste`                    | Select simplified technical English                                    |
| `set situation sbar`               | Set the situational framework directly                                 |
| `set signals intent`               | Enable selective intent markers                                        |
| `enable`                           | Enable this session and apply the returned policy                      |
| `disable`                          | Disable this session, retain its records, and stop applying its policy |
| `settings`                         | Print the complete table of session values, defaults, and explanations |
| `set focus on`                     | Save one session setting and apply the returned policy                 |
| `set compact off`                  | Expand the displayed backlog without changing work order               |
| `set threads off`                  | Suspend thread tracking while retaining its records                    |
| `set communication_profile direct` | Apply the direct communication profile to this session                 |
| `profiles`                         | List predefined profiles and the active profile                        |
| `guidelines`                       | List guidelines enabled by the active profile                          |
| `situations`                       | List I-PASS, CAN, CUS, SBAR, and incident reporting formats            |
| `situation preview sbar`           | Inspect a framework without changing session state                     |
| `situation use sbar`               | Apply a framework to future replies in this session                    |
| `situation clear`                  | Remove the session's active framework                                  |
| `languages`                        | List plain and STE-inspired language standards                         |
| `signals`                          | List sender intent and response-status markers                         |
| `defaults show`                    | Show current values and the defaults for new sessions                  |
| `defaults set enabled on`          | Explicitly opt future sessions into automatic startup activation       |
| `defaults set enabled off`         | Keep future sessions off until explicitly invoked                      |

## Individual guidelines

Guidelines are the primary communication controls; profiles are optional bundles. Use `guidelines` for enabled rules grouped by purpose, `guidelines --all` to see disabled rules and their source, and `guidelines --group TYPE` to inspect one category. Types are structure, brevity, precision, evidence, risk, language, and procedures. Use `guideline on ID`, `guideline off ID`, or `guideline reset ID` to override or restore an individual rule; `guideline group TYPE on|off|reset` does the same for a category. `guideline reset all` clears overrides. Only the enabled effective rules apply. Changes do not implicitly enable Dialogue. Never silently toggle guidelines as a side effect of ordinary task wording.

## Guided setup

When the user invokes `setup`, run the CLI `setup` overview. Present **one question at a time**. Ask exactly these three questions, using options and descriptions from the tool's output:

1. **Comms**: `pyramid`, `direct`, `efficient`, `plain`, or `custom` (start with no enabled rules; configure guidelines individually). Presets only set baseline guidelines. Individual overrides remain in effect.
2. **Style**: `plain` or `ste` (STE-inspired, not ASD-STE100 compliant).
3. **Workflow**: `quiet`, `automatic`, `verified`, `status`, `escalation`, `handoff`, `safety`, or `incident`. A workflow selects both situational formatting and signal semantics; explain that individual settings remain editable.

Retain the selected values in the current conversation only until question three is answered. Never invoke a state-changing command during questions 1 or 2. After question three, call `setup apply --comms VALUE --style VALUE --workflow VALUE` once with the three validated values. The CLI validates them and writes all four underlying settings atomically. Show the short resulting configuration; it does not implicitly enable Dialogue. If a user cancels, do not write anything. If a value is unclear, clarify only that question. The setup overview and `help` must work even when Dialogue is disabled.

## Manual configuration

`set enabled on/off` is equivalent to enabling/disabling. Other settings never implicitly enable the plugin.
The simple setting names are `comms`, `style`, `situation`, `signals`, `enabled`, `threads`, `focus`, and `compact`. Per-guideline changes use the `guideline` command, not `set`. Existing full names `communication_profile`, `language_standard`, and `signaling` remain supported. Both `set <setting> <value>` and `defaults set <setting> <value>` accept these names.
Booleans accept `on/off` or `true/false`. `comms` accepts `pyramid/direct/efficient/plain/custom`; `style` accepts `plain/ste` (`ste-inspired` is the stored value); `situation` accepts `none/auto/sbar/ipass/can/cus/methane`; `signals` accepts `off/intent/full`. Legacy `set response_style pyramid/plain` is supported as an alias.
Defaults affect only sessions that have not yet saved a snapshot. Existing sessions keep their values.
A session's explicit off remains off after restart, resume, and compaction, even when defaults enable new sessions.
The hook restores saved policy; the model must never invent a reason to turn it on.

For situational frameworks, use `situations` to list, `situation preview NAME` to inspect without changing state, and `set situation NAME` to change the current session. Legacy `situation use NAME` and `situation clear` remain supported. `auto` selects a framework only when a task clearly matches it. Never activate dialogue from ordinary wording. Use `languages` and `signals` to list their available options.
A user may request a framework for one response without setting the session default: preview its definition, apply it to that response only, and preserve saved state. Do not automatically open a decision thread for an ordinary writing request.

After enabling or changing settings, follow the tool's returned policy. The rule sources are [threads.md](threads.md), [guidelines.json](guidelines.json), and [profiles.json](profiles.json); the tool selects the applicable parts.
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
