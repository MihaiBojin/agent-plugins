# Dialogue testbed

The testbed runs the dialogue plugin under each of its settings with `claude -p` and `codex exec`. Each run follows a
scripted conversation, and the testbed saves what the agent said and did in one directory per variant. Use it to see
which settings, rules and commands change what an agent produces, and which ones do not.

It runs on your machine with your own Claude Code and Codex logins. Python 3.9 or newer, standard library only.

```sh
cd testbed/dialogue
make render                                   # the policy of every configuration; no model, no cost
make plan                                     # the cases a run would execute, and what they would cost
make run                                      # Claude haiku and Codex gpt-6-luna at low effort
make run CLAUDE_MODEL=sonnet CODEX_MODEL=     # Claude sonnet only
make run ARGS='--suite threads --repeat 3'
make clean                                    # delete out/ and any scratch space a run left behind
```

## Two tiers

`render` needs no model. It seeds a fresh state directory with each of the 1,050 combinations of `comms`, `style`,
`situation`, `signals` and the thread mode, runs the plugin's own SessionStart hook, and saves the policy the hook
injects. `report.md` then lists:

- setting values that give the same policy in every context, such as `comms custom` and `comms plain`
- the size of each policy against the 10,000 characters that Claude Code puts into the conversation, and against the
  `additionalContextLimit` in `hooks/codex.json`
- lines a policy prints more than once, and pairs of rules that cannot both hold
- the situation and signals pairs that the setup workflows reach
- command forms that leave the same saved settings, such as `situation use sbar` and `set situation sbar`
- how much of each listing command `help` already prints, and which commands are read-only

`run` starts real agent sessions, one per case. A case is one agent, one scenario, one configuration and one repeat.

## Suites

`data/suites.json` pairs each setting with the scenarios where it can change the reply. The default plan runs these:

| Suite       | Configurations                                                   | Scenarios                                  |
| ----------- | ---------------------------------------------------------------- | ------------------------------------------ |
| `baseline`  | dialogue disabled, and the base configuration                    | every task scenario                        |
| `comms`     | each communication profile                                       | questions, a comparison, a code change     |
| `style`     | each language style                                              | questions, a procedure, a code change      |
| `situation` | each situational framework                                       | an escalation, a handoff, an incident, ... |
| `signals`   | each signaling mode                                              | ownership of a task, a safety stop, ...    |
| `threads`   | focus and compact on and off, and threads off                    | decisions, thread markers, the `=/` walk   |
| `conflicts` | `ste` with threads off; `ste` with `ipass` and `intent` together | a procedure, a handoff, a safety stop      |
| `workflows` | the eight setup workflows                                        | a question, ownership, escalation, handoff |
| `commands`  | the base configuration, or disabled for `cmd-enable`             | each command, typed in the conversation    |

The base configuration is what `enable` gives a fresh session: `pyramid.plain.none.off.focus-compact` today. The
testbed reads the base, the profiles, the situations and the guidelines from the plugin, so a plugin that adds or
removes a value changes the plan with it.

Two suites run only when asked:

- `--suite guidelines`: the `custom` profile with exactly one guideline on, for each of the 35 guidelines.
- `--full`: every combination of the five settings on every task scenario, about 15,800 sessions for each agent.
  Run `make plan-full` first to see the estimate.

A case that two suites ask for runs once. `variant.json` lists every suite that asked for it.

## Choosing models and cases

```sh
python3 testbed.py plan --agent claude:haiku --agent codex:gpt-6-luna:low
python3 testbed.py run --agent claude:opus:high --scenario decisions --config focus --repeat 3
```

| Option                           | Effect                                                              |
| -------------------------------- | ------------------------------------------------------------------- |
| `--agent CLIENT:MODEL[:EFFORT]`  | Add an agent. `claude` takes `--model` aliases or IDs.              |
| `--suite NAME`                   | Run only these suites                                               |
| `--scenario ID`                  | Run only these scenarios                                            |
| `--config TEXT`                  | Run only configurations whose name contains `TEXT`                  |
| `--limit N`                      | Run only the first N scenario and configuration pairs               |
| `--repeat N`                     | Run each case N times, to see how much one setting varies by itself |
| `--jobs N`                       | Sessions at a time; 4 by default                                    |
| `--max-usd X`                    | Start no new session once the run has spent X dollars               |
| `--calibrate RUN_DIR`            | Estimate from the tokens per turn measured in an earlier run        |
| `--out DIR`                      | Write to DIR; complete variants already there are kept              |
| `--plugin PATH` (before command) | Test another copy of the plugin, such as one on another branch      |

The Makefile passes `CLAUDE_MODEL`, `CLAUDE_EFFORT`, `CODEX_MODEL`, `CODEX_EFFORT` and `JOBS` as these options, and
`ARGS` as anything else.

## Cost

`plan`, and `run` before it starts, print sessions, turns, tokens, dollars and hours for each agent. Prices are in
`data/pricing.json`, in dollars per million tokens. A model with no price there gets a token estimate only.

- Claude reports what each turn cost. `variant.json` and `index.csv` record that figure.
- Codex reports tokens. The testbed prices them at the rates in `data/pricing.json`. Under a ChatGPT sign-in, Codex
  usage counts against the plan's limits, so the dollar figure is what the same tokens cost through the API.
- The default tokens per turn come from a smoke run. After a cheap run, pass `--calibrate out/latest-run` so the
  estimate for a larger model uses the tokens that run measured.

`run` asks before it starts. `--yes` skips the question.

## What each session runs with

Each case gets a copy of `fixture/`, a small service with known facts and known gaps, as a new git repository. The
copy is in a scratch directory outside this repository, so neither client reads this repository's `AGENTS.md` or
`CLAUDE.md`. Each case also gets its own `DIALOGUE_STATE_DIR`. The testbed writes the configuration into it with
`defaults set`, so the session the client starts takes the configuration as its snapshot.

Claude Code runs as:

- `--setting-sources project,local`, so your `CLAUDE.md`, rules, memory and installed plugins stay out of the session
  while your login still works
- `--plugin-dir` with a copy of the plugin made when the run starts, so editing the plugin during a run changes nothing
- one process for the whole conversation, fed one message per turn over `--input-format stream-json`
- `--no-session-persistence`
- tools limited to Read, Glob, Grep, Edit, Write, the dialogue tool, `python3 -m unittest`, `git diff`, `git status`
  and `ls`

Codex runs as:

- a throwaway `CODEX_HOME` holding a link to your `auth.json` and the same copy of the plugin, installed from a local
  marketplace, with remote plugins off
- `codex exec` for the first turn and `codex exec resume` for each later one, with the `workspace-write` sandbox and
  the state directory writable
- `--dangerously-bypass-hook-trust`, because a new `CODEX_HOME` has no record of trusting the plugin's hook

Codex has no way to keep one process across turns. Each `resume` runs the SessionStart hook again, so a Codex session
receives the policy once per turn, while a Claude session receives it once. `variant.json` records the count for
Codex as `policy_injections`.

Claude Code denies a Bash call when any part of it falls outside the allowed tools, such as `D=.../dialogue; $D thread
open ...`. The agent then gets "This command requires approval" and usually retries with a plain call. The transcript
marks the denied call as failed, and `failed_tool_calls` counts it. The allowed tools are in
`claude_allowed_tools()` in `clients.py`.

## Scenarios

`data/scenarios.json` holds the scripted user turns. Task scenarios ask for work; command scenarios type dialogue
commands. A turn can use three placeholders, filled in from the saved state just before the turn is sent:

| Placeholder     | Becomes                                                                |
| --------------- | ---------------------------------------------------------------------- |
| `{cmd}`         | `/dialogue:` for Claude, `$dialogue:` for Codex                        |
| `{active}`      | the active thread, else the first open thread, else `1`                |
| `{recommended}` | that thread's recommended live option, else its first live one, else a |

`turns.json` keeps the template and the text that was sent.

## Output

Nothing under `out/` is checked in. Every directory holds one variant only.

```text
out/
  latest-run -> 20261117-120000-run
  latest-render -> 20261117-115500-render
  20261117-115500-render/
    report.md                  findings across every configuration
    index.csv                  one row per configuration: size, sections, repeats, conflicts
    analysis.json              the data behind report.md
    policies/<config>.md       the policy one configuration injects
  20261117-120000-run/
    run.json                   agents, plugin version, client versions, estimate and spend
    index.csv                  one row per turn of every variant: settings and counts, no reply text
    summary.md                 one table per scenario, one row per variant, linking to its transcript
    cases/<agent>/<scenario>/<config>/r<N>/
      transcript.md            the conversation: user turns, tool calls, replies, threads after each turn
      variant.json             agent, scenario, settings, plugin, policy size, status, cost
      policy.md                the policy the session started with
      turns.json               each turn: text sent, reply, tool calls, usage, saved state after it
      metrics.json             the counts for each turn
      events.jsonl             the client's raw event stream
      stderr.log               the client's stderr
      workspace.diff           what the agent changed in the workspace, when it changed something
      codex-rollout.jsonl      Codex only: the session as Codex recorded it, including injected context
```

A configuration's name lists every setting in order: `comms.style.situation.signals.threads`, for example
`efficient.ste.auto.intent.focus-compact`. A guideline override adds `.+id` or `.-id`. A disabled plugin is `disabled`.

The counts in `metrics.json` and `index.csv` come from patterns, not from reading: words, sentence length,
contractions, numbered items, tables, em-dashes, the `### DECISIONS` heading, thread headings and options, the
compact footer, intent and response markers, framework field labels, narration before tool calls, dialogue tool
calls, and the threads and settings saved after the turn. They point at transcripts worth reading. `make report`
recomputes them for a run after the metrics change.

## Files outside `out/`

- The scratch directory, `$TMPDIR/dialogue-testbed` unless `DIALOGUE_TESTBED_WORK` names another, holds the
  workspaces, the state directories and the Codex home while a run lasts. The run deletes each case's part when the
  case ends and the rest when the run ends.
- Claude Code creates a directory under `~/.claude/projects` for each workspace. The testbed deletes it when the case
  ends. It deletes only directories whose names contain `dialogue-testbed`.

## Tests

`make test` checks the parts that need no model: the matrix, placeholders, event parsing, metrics, prices and the
seeded policy. `npm run test:python` at the repository root runs them too.
