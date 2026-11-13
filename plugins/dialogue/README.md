# dialogue

Dialogue stores configurable communication guidelines and unresolved decisions for each Claude Code or Codex session. Enable it explicitly, focus on one issue, and keep the rest in a saved backlog.

Python 3.9 or newer and Bash are required. The Python implementation uses only the standard library; no pip or npm packages are needed at runtime. The command and hook adapters support macOS and Linux. Native Windows is not validated.

## Install and invoke

| Client      | Install from the mihaibojin marketplace     | Explicit command     |
| ----------- | ------------------------------------------- | -------------------- |
| Claude Code | `claude plugin install dialogue@mihaibojin` | `/dialogue:dialogue` |
| Codex       | `codex plugin add dialogue@mihaibojin`      | `$dialogue:dialogue` |

Add `MihaiBojin/agent-plugins` as a marketplace first if it is not already registered. Start a new session after installation and trust the plugin's hooks when the client asks.

Claude Code shows subcommand syntax in the autocomplete hint for `/dialogue:dialogue`. Codex lists subcommands in the skill picker description. Use `/dialogue:dialogue help` or `$dialogue:dialogue help` to see commands, setting names, and accepted values without enabling the plugin.

Installation does not enable response behavior. **Start with `help`** to see every option or `setup` for a guided three-question configuration. A bare invocation enables the current session. Append `settings` to inspect current values without enabling anything. Append `disable` to stop applying the policy while retaining records.

## Start here: help and setup

```text
/dialogue:dialogue help
/dialogue:dialogue setup
```

Codex uses `$dialogue:dialogue`. Help lists commands, profiles, language styles, situational frameworks, signaling modes, and thread controls. It does not require an active session or change state.

Setup asks **three questions, one at a time**:

1. **Comms**: `pyramid` (answer, reasons and evidence), `direct` (concise and action-oriented), `efficient` (low-token), `plain` (no response rules), or `custom` (start empty and enable guidelines individually). Presets select guideline baselines; individual overrides take precedence.
2. **Style**: `plain` (normal technical English), `ste` (STE-inspired controlled English; not official compliance).
3. **Workflow**: `quiet` (no framework/signals), `automatic` (auto framework + intent), `verified` (auto + full acknowledgments), `status` (CAN), `escalation` (SBAR), `handoff` (I-PASS), `safety` (CUS), `incident` (M/ETHANE).

All choices are saved **once after the third answer**. Cancelling does not change state. Setup preserves whether Dialogue is enabled and leaves decision-thread settings unchanged. The workflow choice maps to `situation` and `signals`; both can be adjusted independently afterward.

### Short commands

```text
/dialogue:dialogue set comms efficient
/dialogue:dialogue set style ste
/dialogue:dialogue set situation sbar
/dialogue:dialogue set signals intent
```

`comms`, `style` and `signals` are short names for `communication_profile`, `language_standard` and `signaling`, and either name works. `situation use sbar` does the same as `set situation sbar`.

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

| Request after the skill name | Result                                                                  |
| ---------------------------- | ----------------------------------------------------------------------- |
| `settings`                   | Show every setting, session value, new-session default, and explanation |
| `set focus off`              | Allow discussion of several relevant issues                             |
| `set compact on`             | Show relevant threads with a count of other open threads                |
| `set threads off`            | Suspend numbering and tracking, retaining the records                   |
| `set comms direct`           | Apply the direct communication profile                                  |
| `profiles`                   | Show preset descriptions and the selected profile                       |
| `guidelines`                 | List the guidelines enabled in the current session                      |
| `defaults set enabled on`    | Explicitly enable automatic activation for future sessions              |
| `defaults set enabled off`   | Make future sessions opt-in again                                       |

The available settings are `enabled`, `threads`, `focus`, `compact`, `communication_profile`, `situation`, `language_standard`, and `signaling`. Fresh defaults are disabled, with threads, focus, and compact enabled once activated, and the `pyramid` communication profile selected. Booleans accept `on/off` or `true/false`; communication profiles accept `pyramid/direct/efficient/plain/custom`. Settings saved under the older `response_style` key load as `communication_profile`. Focus and compact have no effect while threads are disabled.

## Communication profiles

Communication rules are defined once in [guidelines.json](skills/dialogue/guidelines.json), each with an ID, category, name, and short description. [profiles.json](skills/dialogue/profiles.json) contains optional baseline bundles. Individual guideline overrides take precedence; presets do not add hidden instructions.

| Profile     | Behavior                                                                                                                                                       |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pyramid`   | Answer first, then reasons that do not overlap, each with its evidence; a verdict for implementation questions, one recommendation, and tables for comparisons |
| `direct`    | Concise, factual, and action-oriented; reports changes only and puts exceptions first                                                                          |
| `efficient` | Fewer guidelines for routine coding tasks; routine replies take one to three sentences                                                                         |
| `plain`     | No communication guidelines                                                                                                                                    |
| `custom`    | No preset guidelines; enable them individually                                                                                                                 |

Use `profiles` to compare optional presets and `guidelines` to see effective rules grouped by type. Change the current session with `set comms direct`, or new-session defaults with `defaults set communication_profile direct`. Disabled sessions have no active guidelines. Existing sessions retain their saved profiles.

## Individual guidelines

Use the individual guideline controls instead of a preset if you prefer a custom combination.

```text
/dialogue:dialogue guidelines
/dialogue:dialogue guidelines list
/dialogue:dialogue guidelines group list
/dialogue:dialogue guidelines group list language
/dialogue:dialogue guideline enable terminology
/dialogue:dialogue guideline disable no_narration
/dialogue:dialogue guideline reset no_narration
/dialogue:dialogue guideline group enable procedures
/dialogue:dialogue guideline group reset procedures
/dialogue:dialogue guideline reset all
/dialogue:dialogue guideline --default enable bluf
```

Each guideline belongs to one group: **structure**, **brevity**, **precision**, **evidence**, **risk**, **language**, or **procedures**. Guidelines with an ASD-STE100 Issue 9 source form the `style ste` bundle. They are adaptations, not a certification of compliance with the standard. Individual overrides disable or restore any one of them.

`guidelines list` reports each rule's effective state and whether the profile, the style or an override set it. `guidelines group list` shows the count per group; append a group to inspect its rules. Overrides persist per session and take priority over profile and style bundles, and resetting one restores the inherited value. `guideline --default enable|disable|reset ID` and `guideline --default group enable|disable|reset TYPE` change the defaults for future sessions only. `guideline on|off ID`, `guideline group TYPE on|off|reset` and `guidelines --all|--group` are aliases of these commands. Disabling Dialogue turns off every response policy and keeps the saved choices.

The `custom` preset starts with no guidelines enabled, for choosing rules one at a time.

## Situational frameworks

The [situational catalog](skills/dialogue/situations.json) defines SBAR (escalation), I-PASS (handoff and responsibility transfer), CAN (operational updates), CUS (safety escalation), and an engineering adaptation of M/ETHANE (initial major-incident report). These are _optional response structures_, separate from the selected communication profile.

```text
/dialogue:dialogue situations
/dialogue:dialogue situation preview sbar
/dialogue:dialogue situation use can
/dialogue:dialogue situation clear
/dialogue:dialogue set situation auto
```

Preview is read-only. Use selects the protocol for this session. Clear resets it to none. Auto instructs the agent to select a framework only for an explicit matching request; it does not format every message. A single-message framework request can be answered without changing saved settings. Do not invent details to fill fields.

## Language and communication signals

`languages` lists the language standards; `set style ste` applies a simplified, controlled technical-English style inspired by ASD-STE100. This is not official ASD-STE100 compliance or a vocabulary validator. `set style plain` removes it.

`signals` lists the intent and response markers from [signals.json](skills/dialogue/signals.json). `set signals intent` permits sender-intent markers such as FYI, REQUEST, DECISION and WARNING. `set signals full` also defines response statuses such as ACK, ACCEPTED, BLOCKED and DONE. WARNING and CAUTION are the two risk levels: `signals.json` defines them, and the `warnings` guideline, I-PASS, CUS and M/ETHANE use the same two words and print the same definitions. `off` is the default: no marker policy applies. The agent should not prepend a marker to every message.

## Templates and plugin boundaries

Dialogue controls _how_ a response is communicated. Drafting reusable artifacts such as decision requests, status updates, handoffs, incident reports, project kickoffs, and PR descriptions can use these frameworks, but a future template library should own the actual document bodies and field schemas. Docket is for numbered, reviewed, immutable records, such as RFCs and decision records; it is not a natural owner of one-off status messages or PR templates.

## Session persistence

The startup hook takes a snapshot of defaults for each new session, including disabled sessions. Resume and compaction reload that session's saved settings. A change in one session cannot change another's settings, and changing defaults does not revise existing snapshots. New forks use their own session ID and take fresh defaults.

Claude blocks implicit skill invocation with `disable-model-invocation: true`. Codex uses `policy.allow_implicit_invocation: false`. The hook emits no conversation policy for a disabled startup. A disabled fork, or a resumed conversation without a saved snapshot, receives a short reset notice so inherited instructions cannot target the parent session. An explicit session disable wins over an enabled default.

Settings and thread records live under `${XDG_STATE_HOME:-~/.local/state}/dialogue/`, outside the plugin cache. `DIALOGUE_STATE_DIR` selects another directory, useful for tests. Defaults are in `defaults.json`; records are in `sessions/<client>/<session-id>.json`. Both clients share defaults but keep separate session records. Settings inspection does not create files.

Every mutation takes an operating-system lock and writes a temporary file in the destination directory before atomically replacing the JSON file. A corrupt record produces an error and remains untouched. Do not manually edit records while a session uses them.

## Threads

Each decision gets a permanent ID. Child decisions use dotted IDs; alternatives use letters. Closing a parent closes its descendants. Reopening a child reopens its ancestors. Closed numbers and spent letters are never reused.

Focus mode keeps work on the active issue and saves unrelated findings for later. A blocker of the active issue is shown immediately. Compact display limits repeated backlog text and ends with a computed count, for example:

> 4 other open threads. Type `=/` to go through them one at a time or `=//` to see them all.

Both commands first check the conversation for decisions nobody recorded. `=//` then shows every open thread with its details and live choices. `=/` shows the first open thread with its details; once the user answers or defers it, the agent shows the next open thread in ID order, and so on until none follows or the user types `=//`. A child thread opened by an answer comes up next. A user can pick another thread directly; focus controls work order, not permission to steer the conversation. With compact disabled, all open threads are displayed even when work stays focused on one.

The agent interprets the conversation and calls the tool to record changes. The tool enforces IDs and state transitions; it does not infer decisions from transcripts or guarantee every response follows the style. See [the thread policy](skills/dialogue/threads.md).

## Direct tool use

From the installed plugin directory:

```sh
bin/dialogue --client codex --session YOUR_SESSION_ID settings
bin/dialogue --client codex --session YOUR_SESSION_ID enable
bin/dialogue --client codex --session YOUR_SESSION_ID thread open 'Which storage engine?' --body 'Decide between SQLite and JSON.'
bin/dialogue --client codex --session YOUR_SESSION_ID thread option 1 'Use JSON'
bin/dialogue --client codex --session YOUR_SESSION_ID thread choose 1 a
bin/dialogue --client codex --session YOUR_SESSION_ID disable
```

For Codex, `--session` can use `CODEX_THREAD_ID` from the tool environment. Claude's skill obtains the ID through `${CLAUDE_SESSION_ID}` substitution and passes it explicitly. Hook inputs supply `session_id` on stdin. Commands refuse missing or unsafe IDs rather than guessing from the working directory.

Use `thread --help` for the supported operations. `state` prints all saved session data as JSON, and `render` prints the currently applicable policy. `settings`, `state`, and thread inspection remain available when disabled.

## Using agent-rules alongside dialogue

Use the limited profile from the accompanying agent-rules change before enabling dialogue:

```sh
make install-limited
make project-limited DIR=/path/to/project
make status DIR=/path/to/project
```

Apply the project target only where project rules were installed. The limited profile keeps engineering and repository-prose guidance, with conversation behavior supplied by this plugin. Check for mixed global and project profiles, then start a fresh session. Existing conversations still contain instructions loaded before the switch.

Rollback preserves the full ruleset: disable dialogue, run `make install`, restore any project installation with `make project DIR=...`, and start a fresh session. The plugin never switches profiles or rewrites home instructions when enabled.

## Validation

Run `npm run test:python` from the marketplace root. The tests execute the real tool against temporary state directories and the packaged client hooks against lifecycle payloads. `npm run check` includes these tests along with repository validation.
