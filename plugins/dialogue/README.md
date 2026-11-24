# dialogue

Dialogue sets how Claude Code or Codex writes its replies in one session, and keeps that session's open decisions as numbered threads that survive a resume or a compaction. It does nothing until you enable it.

It needs Python 3.9 or newer and Bash, and no pip or npm packages. It runs on macOS and Linux; native Windows is untested.

## Install

| Client      | Commands                                                                                                | Skills           |
| ----------- | ------------------------------------------------------------------------------------------------------- | ---------------- |
| Claude Code | `claude plugin marketplace add MihaiBojin/agent-plugins`<br>`claude plugin install dialogue@mihaibojin` | `/dialogue:NAME` |
| Codex       | `codex plugin marketplace add MihaiBojin/agent-plugins`<br>`codex plugin add dialogue@mihaibojin`       | `$dialogue:NAME` |

Start a new session after installing, and trust the plugin's hooks when the client asks. A dialogue skill runs only when you type it. The rules from [agent-rules](https://github.com/MihaiBojin/agent-rules) contain no reply or thread rules, so the two install side by side.

Codex's `workspace-write` sandbox blocks the state directory until you allow it. Add the directory to `writable_roots` in `~/.codex/config.toml`, keeping any roots already there, and restart the session:

```toml
[sandbox_workspace_write]
writable_roots = ["/Users/you/.local/state/dialogue"]
```

Use the absolute path on your machine: `$DIALOGUE_STATE_DIR` when it is set, otherwise `$XDG_STATE_HOME/dialogue`, otherwise `~/.local/state/dialogue`. A named permission profile needs the same write access. Without it, writes fail with `Operation not permitted` or `Permission denied` on `.lock` or a state file. Dialogue prints the path and leaves Codex's settings alone, and deleting the lock does not help. The Codex documentation covers [sandbox modes](https://learn.chatgpt.com/docs/config-file/config-advanced#approval-policies-and-sandbox-modes) and [permission profiles](https://learn.chatgpt.com/docs/permissions).

## First run

```text
/dialogue:setup
/dialogue:enable
```

Setup asks three questions, one at a time, and saves all three answers after the last one. Cancelling saves nothing, and setup does not turn dialogue on or off. In a session where dialogue is off, it prints:

```text
Configuration saved: comms=efficient, style=plain, signals=off. Dialogue disabled; enable to apply policy.
```

In Claude Code, enable prints `Dialogue is enabled for claude session <id>.` and then the policy the agent follows from its next reply. `/dialogue:disable` stops it and keeps the saved settings and threads.

## Commands

| Command                                | Result                                                             |
| -------------------------------------- | ------------------------------------------------------------------ |
| `help`                                 | Show commands, setting names and accepted values, changing nothing |
| `enable`                               | Turn dialogue on for this session and apply its policy             |
| `disable`                              | Stop applying the policy, keeping the saved records                |
| `setup`                                | Ask three questions and save the answers                           |
| `settings`                             | Show every setting, its session value, its default and its meaning |
| `state`                                | Print the saved session record as JSON                             |
| `set <key> <value>`                    | Change one setting for this session                                |
| `defaults [show \| set <key> <value>]` | Show or change the defaults for new sessions                       |
| `profiles`                             | List the communication profiles and the one in use                 |
| `languages`                            | List the language styles                                           |
| `signals`                              | List the intent and response-status markers                        |
| `guidelines`                           | List the guidelines and whether each applies                       |
| `guideline`                            | Override one guideline or group, or restore it                     |

## Settings

| Key       | Full name               | Values                                    | Default   |
| --------- | ----------------------- | ----------------------------------------- | --------- |
| `comms`   | `communication_profile` | `pyramid`, `direct`, `efficient`, `plain` | `pyramid` |
| `style`   | `language_standard`     | `plain`, `ste`                            | `plain`   |
| `signals` | `signaling`             | `off`, `intent`, `full`                   | `off`     |
| `enabled` |                         | `on`, `off`                               | `off`     |
| `threads` |                         | `on`, `off`                               | `on`      |
| `focus`   |                         | `on`, `off`                               | `on`      |
| `compact` |                         | `on`, `off`                               | `on`      |

`/dialogue:set focus off` changes this session only. `/dialogue:defaults set focus off` changes the sessions that start after it, and no existing one. `defaults set enabled on` turns dialogue on in every new session. Booleans also accept `true` and `false`. Focus and compact do nothing while threads are off, and `threads off` keeps the saved threads.

## Communication profiles and guidelines

Each rule a profile can apply is one entry in [guidelines.json](policy/guidelines.json): 19 rules in four groups, structure, brevity, risk and language. A profile is a starting set of those rules, defined in [profiles.json](policy/profiles.json):

| Profile     | Rules | Behavior                                                                    |
| ----------- | ----- | --------------------------------------------------------------------------- |
| `pyramid`   | 10    | Answer first, a verdict, one recommendation, tables for comparisons         |
| `direct`    | 8     | Concise and action-oriented; reports changes only and puts exceptions first |
| `efficient` | 7     | For routine coding tasks; routine replies take one to three sentences       |
| `plain`     | 0     | No rules, for turning them on one at a time                                 |

`set style ste` adds the 6 rules adapted from ASD-STE100, such as short sentences and clear pronouns. The style is not ASD-STE100 compliance, and dialogue does not check vocabulary.

An override turns one rule or one group on or off, whatever the profile and the style say:

```text
/dialogue:guidelines list
/dialogue:guideline enable plain_words
/dialogue:guideline group disable risk
/dialogue:guideline reset all
/dialogue:guideline --default enable bluf
```

`guidelines list` shows each rule as on or off and what set it: the profile, the style or an override. `guidelines group list risk` shows one group. `reset` restores the inherited value, and `--default` changes new sessions only. A disabled session applies no rules.

## Escalation and handoff formats

The technical-writer plugin's handoff genre carries SBAR, I-PASS and CUS, and its incident-update and status-update genres carry CAN and M/ETHANE.

## Signals

`set signals intent` lets the agent mark a message that needs it with an intent such as FYI, REQUEST, DECISION or WARNING. `set signals full` adds response statuses such as ACK, BLOCKED and DONE. [signals.json](policy/signals.json) defines them all. WARNING marks irreversible harm and CAUTION recoverable harm; the `warnings` rule prints the same two definitions.

## Threads

Each decision gets a number that is never reused, and its options get letters. The agent records each one with the dialogue tool, puts the answer first, and lists the open decisions last:

```text
---

### DECISIONS

### 6/ whether to tag the release

6a/ (recommended) Tag it now
6b/ Wait for the next release

---

### 7/ whether to delete the leftover file
```

You answer with markers at the start of a line:

| Marker       | Effect                                             |
| ------------ | -------------------------------------------------- |
| `+ subject`  | Open a thread                                      |
| `5+ subject` | Open a thread related to 5/, listed right after it |
| `6a`         | Choose option a of 6/                              |
| `6a/$`       | Reject option a of 6/                              |
| `6/ text`    | Answer 6/ in words                                 |
| `6/`         | Reopen 6/ and show its saved context               |
| `6/$`        | Close 6/                                           |
| `=/`         | Go through the open threads one at a time          |
| `=//`        | Show every open thread with its options            |

Both `=/` and `=//` first record any decision the conversation left unrecorded. With focus on, the agent finishes the active thread and saves unrelated findings for later, except a blocker, which it shows at once. With compact on, a reply shows only the relevant threads and ends with a count:

> 4 other open threads. Type `=/` to go through them one at a time or `=//` to see them all.

The tool assigns numbers and enforces state changes; the agent decides what counts as a decision. [threads.md](policy/threads.md) is the full protocol.

## Sessions and state

Each session takes a copy of the defaults when it starts, so a change in one session never reaches another, and a fork starts from the defaults under its own ID. A disabled fork, or a resumed session with no saved copy, gets a notice to drop any policy it inherited.

The SessionStart hook prints the policy in two parts, because Claude Code passes at most 10,000 characters of one hook's context and replaces anything longer with a file path. The first part holds the profile, style and signals. The second holds the thread protocol, the open threads, and one outcome line for each of the last 10 closed threads, so a resumed or compacted session does not reopen a settled decision.

State lives in `${XDG_STATE_HOME:-~/.local/state}/dialogue/`, or in `$DIALOGUE_STATE_DIR`: `defaults.json`, shared by both clients, and `sessions/<client>/<session-id>.json`. Inspecting settings creates no files. Each write takes a lock and replaces the file atomically, and a corrupt file is reported and left untouched. Do not edit these files while a session uses them.

## Running the tool directly

From the installed plugin directory:

```sh
bin/dialogue --client codex --session YOUR_SESSION_ID enable
bin/dialogue --client codex --session YOUR_SESSION_ID thread open 'Which storage engine?' --body 'Decide between SQLite and JSON.'
bin/dialogue --client codex --session YOUR_SESSION_ID thread option 1 'Use JSON' --recommended
bin/dialogue --client codex --session YOUR_SESSION_ID thread choose 1 a
bin/dialogue --client codex --session YOUR_SESSION_ID thread show 1
```

`thread choose` closes the thread, and `thread show 1` then prints `Outcome: chose 1a/ Use JSON` under it. `--session` defaults to `CODEX_THREAD_ID` for Codex and `CLAUDE_SESSION_ID` for Claude Code, and the tool refuses a missing or unsafe ID instead of guessing one. `thread --help` lists the thread operations, and `render` prints the policy that applies now.
