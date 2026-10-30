# dialogue

Dialogue stores conversation settings and unresolved decisions for each Claude Code or Codex session. Enable it explicitly, focus on one issue, and keep the rest in a saved backlog.

Python 3.9 or newer and Bash are required. The Python implementation uses only the standard library; no pip or npm packages are needed at runtime. The command and hook adapters support macOS and Linux. Native Windows is not validated.

## Install and invoke

| Client      | Install from the mihaibojin marketplace     | Explicit command     |
| ----------- | ------------------------------------------- | -------------------- |
| Claude Code | `claude plugin install dialogue@mihaibojin` | `/dialogue:dialogue` |
| Codex       | `codex plugin add dialogue@mihaibojin`      | `$dialogue`          |

Add `MihaiBojin/agent-plugins` as a marketplace first if it is not already registered. Start a new session after installation and trust the plugin's hooks when the client asks.

Claude Code shows subcommand syntax in the autocomplete hint for `/dialogue:dialogue`. Use `/dialogue:dialogue help` or `$dialogue help` to see commands, setting names, and accepted values without enabling the plugin.

Installation does not enable response behavior. A bare invocation enables the current session. Append `settings` to inspect the table without enabling anything. Append `disable` to stop applying the policy while keeping recorded threads.

| Request after the skill name | Result                                                                  |
| ---------------------------- | ----------------------------------------------------------------------- |
| `settings`                   | Show every setting, session value, new-session default, and explanation |
| `set focus off`              | Allow discussion of several relevant issues                             |
| `set compact on`             | Show relevant threads with a count of other open threads                |
| `set threads off`            | Suspend numbering and tracking, retaining the records                   |
| `set response_style plain`   | Stop applying the plugin's response style                               |
| `defaults set enabled on`    | Explicitly enable automatic activation for future sessions              |
| `defaults set enabled off`   | Make future sessions opt-in again                                       |

The available settings are `enabled`, `threads`, `focus`, `compact`, and `response_style`. Fresh defaults are disabled, with threads, focus, and compact enabled once activated, and Pyramid response style. Booleans accept `on/off` or `true/false`; response style accepts `pyramid/plain`. Focus and compact have no effect while threads are disabled.

## Session persistence

The startup hook takes a snapshot of defaults for each new session, including disabled sessions. Resume and compaction reload that session's saved settings. A change in one session cannot change another's settings, and changing defaults does not revise existing snapshots. New forks use their own session ID and take fresh defaults.

Claude blocks implicit skill invocation with `disable-model-invocation: true`. Codex uses `policy.allow_implicit_invocation: false`. The hook emits no conversation policy for a disabled startup. A disabled fork, or a resumed conversation without a saved snapshot, receives a short reset notice so inherited instructions cannot target the parent session. An explicit session disable wins over an enabled default.

Settings and thread records live under `${XDG_STATE_HOME:-~/.local/state}/dialogue/`, outside the plugin cache. `DIALOGUE_STATE_DIR` selects another directory, useful for tests. Defaults are in `defaults.json`; records are in `sessions/<client>/<session-id>.json`. Both clients share defaults but keep separate session records. Settings inspection does not create files.

Every mutation takes an operating-system lock and writes a temporary file in the destination directory before atomically replacing the JSON file. A corrupt record produces an error and remains untouched. Do not manually edit records while a session uses them.

## Threads

Each decision gets a permanent ID. Child decisions use dotted IDs; alternatives use letters. Closing a parent closes its descendants. Reopening a child reopens its ancestors. Closed numbers and spent letters are never reused.

Focus mode keeps work on the active issue and saves unrelated findings for later. A blocker of the active issue is shown immediately. Compact display limits repeated backlog text and ends with a computed count, for example:

> 4 other open threads. Type `=/` for headings or `=//` for details.

Those audit commands show all open threads. A user can pick another thread directly; focus controls work order, not permission to steer the conversation. With compact disabled, all open threads are displayed even when work stays focused on one.

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
