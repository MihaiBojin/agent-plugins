# dialogue

Dialogue stores configurable communication guidelines and unresolved decisions for each Claude Code or Codex session. Enable it explicitly, focus on one issue, and keep the rest in a saved backlog.

Python 3.9 or newer and Bash are required. The Python implementation uses only the standard library; no pip or npm packages are needed at runtime. The command and hook adapters support macOS and Linux. Native Windows is not validated.

## Install and invoke

| Client      | Install from the mihaibojin marketplace     | Commands         |
| ----------- | ------------------------------------------- | ---------------- |
| Claude Code | `claude plugin install dialogue@mihaibojin` | `/dialogue:NAME` |
| Codex       | `codex plugin add dialogue@mihaibojin`      | `$dialogue:NAME` |

Add `MihaiBojin/agent-plugins` as a marketplace first if it is not already registered. Start a new session after installation and trust the plugin's hooks when the client asks.

Installation does not enable response behavior; `enable` does. Each command is a skill, so both clients list it with its own description:

| Command                                | Result                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------- |
| `help`                                 | Show commands, setting names and accepted values, changing nothing     |
| `enable`                               | Turn dialogue on for this session and apply its policy                 |
| `disable`                              | Stop applying the policy, keeping the saved records                    |
| `setup`                                | Ask three questions and save the answers                               |
| `settings`                             | Show every setting, session value, new-session default and explanation |
| `state`                                | Print the saved session record as JSON                                 |
| `set <key> <value>`                    | Change one setting for this session                                    |
| `defaults [show \| set <key> <value>]` | Show or change the defaults for future sessions                        |
| `profiles`                             | List the communication profiles and the one in use                     |
| `languages`                            | List the language styles                                               |
| `signals`                              | List the intent and response-status markers                            |
| `situations [name]`                    | List the situational frameworks, or show the fields of one             |
| `guidelines`                           | List the guidelines and whether each applies                           |
| `guideline`                            | Override one guideline or group, or restore it                         |

## Start here: help and setup

```text
/dialogue:help
/dialogue:setup
```

Help lists commands, profiles, language styles, situational frameworks, signaling modes, and thread controls. It does not require an active session or change state.

Setup asks **three questions, one at a time**:

1. **Comms**: `pyramid` (answer first, with a verdict and tables), `direct` (concise and action-oriented), `efficient` (low-token), or `plain` (no response rules, and the start for turning guidelines on one at a time). Presets select guideline baselines; individual overrides take precedence.
2. **Style**: `plain` (normal technical English), `ste` (STE-inspired controlled English; not official compliance).
3. **Signals**: `off` (no markers), `intent` (sender-intent labels), `full` (intent and response-status labels).

All choices are saved **once after the third answer**. Cancelling does not change state. Setup preserves whether Dialogue is enabled and leaves decision-thread settings unchanged.

### Short commands

```text
/dialogue:set comms efficient
/dialogue:set style ste
/dialogue:set signals intent
```

`comms`, `style` and `signals` are short names for `communication_profile`, `language_standard` and `signaling`, and either name works.

### Codex state permissions

Dialogue writes settings and threads outside the workspace. Codex's `workspace-write` sandbox needs permission for the state directory, including its lock and temporary files. In `~/.codex/config.toml` (or `$CODEX_HOME/config.toml`), add the directory to the existing `writable_roots` array under `[sandbox_workspace_write]`. Create the table if absent; preserve any other roots and settings.

```toml
[sandbox_workspace_write]
writable_roots = ["/absolute/path/to/your/home/.local/state/dialogue"]
```

Use an absolute path for your machine. If `DIALOGUE_STATE_DIR` is set, authorize that directory instead. Otherwise, if `XDG_STATE_HOME` is set, authorize its `dialogue` subdirectory. The hook and tool commands must use the same state directory.

Restart the Codex session after changing its permissions. For a named permission profile, grant the state directory write access in that profile. See the [official Codex sandbox configuration](https://learn.chatgpt.com/docs/config-file/config-advanced#approval-policies-and-sandbox-modes) and [permission profiles](https://learn.chatgpt.com/docs/permissions).

An `Operation not permitted` or `Permission denied` error on `.lock` or a state file can indicate a sandbox restriction or filesystem permissions. Check both. Dialogue reports the affected path and Codex setup guidance; it does not change Codex permissions automatically. Authorize the state directory only. Deleting the lock does not grant access.

### Session settings

| Command                              | Result                                                     |
| ------------------------------------ | ---------------------------------------------------------- |
| `/dialogue:set focus off`            | Allow discussion of several relevant issues                |
| `/dialogue:set compact on`           | Show relevant threads with a count of other open threads   |
| `/dialogue:set threads off`          | Suspend numbering and tracking, retaining the records      |
| `/dialogue:set comms direct`         | Apply the direct communication profile                     |
| `/dialogue:defaults set enabled on`  | Explicitly enable automatic activation for future sessions |
| `/dialogue:defaults set enabled off` | Make future sessions opt-in again                          |

The available settings are `enabled`, `threads`, `focus`, `compact`, `communication_profile`, `language_standard`, and `signaling`. Fresh defaults are disabled, with threads, focus, and compact enabled once activated, and the `pyramid` communication profile selected. Booleans accept `on/off` or `true/false`; communication profiles accept `pyramid/direct/efficient/plain`; a session saved with `custom` loads as `plain`. Settings saved under the older `response_style` key load as `communication_profile`, and a saved `situation` is dropped. Focus and compact have no effect while threads are disabled.

## Communication profiles

Communication rules are defined once in [guidelines.json](policy/guidelines.json), each with an ID, category, name, and short description. [profiles.json](policy/profiles.json) contains optional baseline bundles. Individual guideline overrides take precedence; presets do not add hidden instructions.

| Profile     | Behavior                                                                                             |
| ----------- | ---------------------------------------------------------------------------------------------------- |
| `pyramid`   | Answer first; a verdict for implementation questions, one recommendation, and tables for comparisons |
| `direct`    | Concise, factual, and action-oriented; reports changes only and puts exceptions first                |
| `efficient` | Fewer guidelines for routine coding tasks; routine replies take one to three sentences               |
| `plain`     | No communication guidelines                                                                          |

Use `profiles` to compare optional presets and `guidelines` to see effective rules grouped by type. Change the current session with `set comms direct`, or new-session defaults with `defaults set communication_profile direct`. Disabled sessions have no active guidelines. Existing sessions retain their saved profiles.

## Individual guidelines

Use the individual guideline controls instead of a preset if you prefer a custom combination.

```text
/dialogue:guidelines
/dialogue:guidelines list
/dialogue:guidelines group list
/dialogue:guidelines group list language
/dialogue:guideline enable plain_words
/dialogue:guideline disable no_narration
/dialogue:guideline reset no_narration
/dialogue:guideline group enable risk
/dialogue:guideline group reset risk
/dialogue:guideline reset all
/dialogue:guideline --default enable bluf
```

Each guideline belongs to one group: **structure**, **brevity**, **risk**, or **language**. Guidelines with an ASD-STE100 Issue 9 source form the `style ste` bundle. They are adaptations, not a certification of compliance with the standard. Individual overrides disable or restore any one of them.

`guidelines list` reports each rule's effective state and whether the profile, the style or an override set it. `guidelines group list` shows the count per group; append a group to inspect its rules. Overrides persist per session and take priority over profile and style bundles, and resetting one restores the inherited value. `guideline --default enable|disable|reset ID` and `guideline --default group enable|disable|reset TYPE` change the defaults for future sessions only. `guideline on|off ID`, `guideline group TYPE on|off|reset` and `guidelines --all|--group` are aliases of these commands. Disabling Dialogue turns off every response policy and keeps the saved choices.

The `plain` profile starts with no guidelines enabled, for choosing rules one at a time.

## Situational frameworks

The [situational catalog](policy/situations.json) defines SBAR (escalation), I-PASS (handoff and responsibility transfer), CAN (operational updates), CUS (safety escalation), and an engineering adaptation of M/ETHANE (initial major-incident report). These are _optional response structures_, separate from the selected communication profile.

```text
/dialogue:situations
/dialogue:situations sbar
```

Both are read-only. The policy does not mention the frameworks: a user asks for one by name in the request it applies to, and the agent writes that reply in its fields.

## Language and communication signals

`languages` lists the language standards; `set style ste` applies a simplified, controlled technical-English style inspired by ASD-STE100. This is not official ASD-STE100 compliance or a vocabulary validator. `set style plain` removes it.

`signals` lists the intent and response markers from [signals.json](policy/signals.json). `set signals intent` permits sender-intent markers such as FYI, REQUEST, DECISION and WARNING. `set signals full` also defines response statuses such as ACK, ACCEPTED, BLOCKED and DONE. WARNING and CAUTION are the two risk levels: `signals.json` defines them, and the `warnings` guideline and the I-PASS, CUS and M/ETHANE previews use the same two words and print the same definitions. `off` is the default: no marker policy applies. The agent should not prepend a marker to every message.

## Templates and plugin boundaries

Dialogue controls _how_ a response is communicated. Drafting reusable artifacts such as decision requests, status updates, handoffs, incident reports, project kickoffs, and PR descriptions can use these frameworks, but a future template library should own the actual document bodies and field schemas. Docket is for numbered, reviewed, immutable records, such as RFCs and decision records; it is not a natural owner of one-off status messages or PR templates.

## Session persistence

The SessionStart hook prints the policy in two parts, `hook` and `hook --part threads`, because Claude Code puts a hook's context into the conversation only up to 10,000 characters and gives the model a short preview and a file path for anything longer. The first part carries the profile, style and signals; the second carries the thread protocol, the saved open threads and a one-line outcome for each of the last 10 closed threads by ID, so a resumed or compacted session does not reopen a settled decision. `thread show ID` prints the same outcome under a closed thread. The startup hook takes a snapshot of defaults for each new session, including disabled sessions. Resume and compaction reload that session's saved settings. A change in one session cannot change another's settings, and changing defaults does not revise existing snapshots. New forks use their own session ID and take fresh defaults.

Claude blocks implicit skill invocation with `disable-model-invocation: true`. Codex uses `policy.allow_implicit_invocation: false`. The hook emits no conversation policy for a disabled startup. A disabled fork, or a resumed conversation without a saved snapshot, receives a short reset notice so inherited instructions cannot target the parent session. An explicit session disable wins over an enabled default.

Settings and thread records live under `${XDG_STATE_HOME:-~/.local/state}/dialogue/`, outside the plugin cache. `DIALOGUE_STATE_DIR` selects another directory, useful for tests. Defaults are in `defaults.json`; records are in `sessions/<client>/<session-id>.json`. Both clients share defaults but keep separate session records. Settings inspection does not create files.

Every mutation takes an operating-system lock and writes a temporary file in the destination directory before atomically replacing the JSON file. A corrupt record produces an error and remains untouched. Do not manually edit records while a session uses them.

## Threads

Each decision gets a permanent number; alternatives use letters. A decision that splits into parts becomes one thread per part, numbered in the order to answer them, then the deciding thread last when one is still needed. `5+ subject` opens a thread related to 5/: it takes the next unused number, prints `Related: 5/`, and lists right after 5/, so 7/ related to 5/ lists as 5/, 7/, 6/. Closing 5/ leaves 7/ open. The recommended alternative is added first with `--recommended` and prints as `3a/ (recommended) TEXT`; the thread's body, which carries the reason, follows the alternatives. Closed numbers and spent letters are never reused.

A reply puts its answer first and its decisions last, under a `---` line and a `### DECISIONS` heading, with a `---` line between threads:

```text
---

### DECISIONS

### 6/ whether to tag the release

6a/ (recommended) Tag it now
6b/ Wait for the next release

---

### 7/ whether to delete the leftover file
```

Focus mode keeps work on the active issue and saves unrelated findings for later. A blocker of the active issue is shown immediately. Compact display limits repeated backlog text and ends with a computed count, for example:

> 4 other open threads. Type `=/` to go through them one at a time or `=//` to see them all.

Both commands first check the conversation for decisions nobody recorded. `=//` then shows every open thread with its details and live choices. `=/` shows the first open thread with its details; once the user answers or defers it, the agent shows the next open thread in `thread list` order, and so on until none follows or the user types `=//`. A thread opened by an answer comes up next. A user can pick another thread directly; focus controls work order, not permission to steer the conversation. With compact disabled, all open threads are displayed even when work stays focused on one.

The agent interprets the conversation and calls the tool to record changes. The tool enforces IDs and state transitions; it does not infer decisions from transcripts or guarantee every response follows the style. See [the thread policy](policy/threads.md).

## Direct tool use

From the installed plugin directory:

```sh
bin/dialogue --client codex --session YOUR_SESSION_ID settings
bin/dialogue --client codex --session YOUR_SESSION_ID enable
bin/dialogue --client codex --session YOUR_SESSION_ID thread open 'Which storage engine?' --body 'Decide between SQLite and JSON.'
bin/dialogue --client codex --session YOUR_SESSION_ID thread option 1 'Use JSON' --recommended
bin/dialogue --client codex --session YOUR_SESSION_ID thread choose 1 a
bin/dialogue --client codex --session YOUR_SESSION_ID disable
```

For Codex, `--session` can use `CODEX_THREAD_ID` from the tool environment. Claude's skill obtains the ID through `${CLAUDE_SESSION_ID}` substitution and passes it explicitly. Hook inputs supply `session_id` on stdin. Commands refuse missing or unsafe IDs rather than guessing from the working directory.

Use `thread --help` for the supported operations. `state` prints all saved session data as JSON, and `render` prints the currently applicable policy. `settings`, `state`, and thread inspection remain available when disabled.

## Using agent-rules alongside dialogue

agent-rules carries no reply or thread rules, so `make install` in agent-rules wires its rules beside dialogue without a conflict. Start a fresh session after installing; a running conversation keeps the instructions it loaded at its start.

## Validation

Run `npm run test:python` from the marketplace root. The tests execute the real tool against temporary state directories and the packaged client hooks against lifecycle payloads. `npm run check` includes these tests along with repository validation.
