# technical-writer benchmark

The benchmark writes six documents with the `write-technical-prose` skill, without it, and with each rule or group of
rules removed. It measures how simple each document reads, and a judge model grades it against every rule of the
skill. A rule earns its place when removing it changes what gets written.

```sh
make plan        # sessions and estimated dollars for the default run
make run         # every group removed in turn, with claude:haiku and codex:gpt-6-luna:low; asks first
make run-rules   # every rule removed in turn, about three times the sessions
make report      # rebuild bench.md and bench.csv for out/latest-run
make test        # the unit tests; no model
make clean       # delete out/ and the scratch space
```

| Variable                        | Default               | Sets                                                                        |
| ------------------------------- | --------------------- | --------------------------------------------------------------------------- |
| `CLAUDE_MODEL`, `CODEX_MODEL`   | `haiku`, `gpt-6-luna` | the writer models; an empty one skips that client                           |
| `CLAUDE_EFFORT`, `CODEX_EFFORT` | none, `low`           | the writers' reasoning effort                                               |
| `JUDGE`                         | `claude:sonnet`       | the model that grades each document                                         |
| `REPEAT`                        | `6`                   | sessions per task and configuration                                         |
| `JOBS`                          | `6`                   | sessions at a time                                                          |
| `ARGS`                          | none                  | anything else for `bench.py`, such as `ARGS='--task runbook --config full'` |

## Configurations

| Name    | Runs                                                                                                                        |
| ------- | --------------------------------------------------------------------------------------------------------------------------- |
| `off`   | the task without the plugin                                                                                                 |
| `full`  | the plugin as it is                                                                                                         |
| `*NAME` | the plugin with one group of rules removed, from [data/groups.json](data/groups.json), or `*dials`, without the dials table |
| `-ID`   | the plugin with one rule removed, with `--units rules`                                                                      |

A configuration without a rule deletes that rule's `### \`id\``section from a copy of`SKILL.md`, up to the next
heading. Every configuration with the plugin starts its prompt with "Use the write-technical-prose skill.", so a short
task cannot skip the skill and leave every rule untested; `off` gets the task as written.

## Tasks

[data/tasks.json](data/tasks.json) lists them. Four reuse the prompt of an eval case in
`plugins/technical-writer/evals/`: a runbook, a postmortem, a design doc and a deprecation notice. Two are short
genres of their own: an incident update and an error message.

## What it measures

| Measure                                   | What it counts                                                   |
| ----------------------------------------- | ---------------------------------------------------------------- |
| Words, sentences                          | prose only: code blocks and inline code are left out             |
| Words per sentence, long sentences        | sentence length, and sentences over 25 words                     |
| Characters per word, long words %         | word length, and the share of words with three syllables or more |
| Grade                                     | the Flesch-Kincaid grade level, from sentence and word length    |
| Passive, em-dashes, contractions          | marks the shared rules forbid                                    |
| Headings, bullets, numbered items, tables | the document's structure                                         |

The judge gets the task, the document and the full text of every rule, whatever the configuration removed. It
answers pass, fail with a reason of up to 20 words, or na for a rule that cannot apply. A rule's pass rate where it
was removed says what the writer does when nobody told it the rule.

## The report

`bench.md` has three tables for each writer model:

- each configuration's mean measures, how often the skill loaded, the share of rules passed and the size of
  `SKILL.md`
- each rule's pass rate without the plugin, with it, and in the configuration that removes it
- each removed unit's p-value and effect, from the dialogue testbed's ablation statistics: every configuration
  but `off` is the null, each task a scenario, and the measures and verdicts the counts

`bench.csv` has one row per session. Each case directory under `out/RUN/cases/` keeps `reply.md`, `metrics.json`,
`grades.json` with the judge's raw answer and reasons, `case.json`, the client's events and its stderr.

## Isolation

Claude Code runs with `--setting-sources project,local`, so your `CLAUDE.md`, rules, memory and installed plugins
stay out, and with only the Read, Glob, Grep and Skill tools. Codex runs read-only with a throwaway `CODEX_HOME`
that holds your login and the plugin copy, or no plugin for `off`. Each session starts in an empty directory.

The benchmark imports the dialogue testbed's client parsers, prices, judge client and statistics from
`../dialogue`, so both report effects the same way.
