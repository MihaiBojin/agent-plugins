# Changelog

## 0.6.0 - 2026-11-14

### Changed

`thread open --parent` is gone, and the agent no longer opens child threads such as 5.1/. A decision with parts becomes one thread per part, numbered in the order to answer them, with the deciding thread last when one is still needed. Sessions saved with dotted IDs still load.

`5+ subject` opens a thread related to 5/. It takes the next unused number, shows `Related: 5/` under its heading, and lists right after 5/, so 7/ related to 5/ lists as 5/, 7/, 6/. Closing 5/ leaves 7/ open, and `=/` walks threads in the order `thread list` prints them.

`thread option ID TEXT --recommended` marks the option the agent recommends. It must be the thread's first live option, and it prints as `3a/ (recommended) TEXT`. Live options print before the thread's body, and thread headings print as `### 3/`.

Replies put informative points in `-` bullets above the first thread heading and never use a numbered list.

### Choices

Saved records with dotted IDs keep loading, and closing 1/ still closes 1.1/ in them. Refusing them would stop every resumed 0.5.0 session that opened a child thread with "invalid thread ID".

The tool refuses `--recommended` on an option added after another live one, rather than reordering the list. The letters then stay in the order they were spent, and `a` is the recommended option whenever one is marked.

## 0.5.0 - 2026-11-13

`=/` goes through the open threads one at a time. It shows the first open thread with its details and live choices, then, once you answer or defer it, the next one in ID order, until none is left or you type `=//`. `=//` shows every open thread with its details, as before. `=/` no longer prints a list of headings; `thread list` still does. The compact footer reads "Type `=/` to go through them one at a time or `=//` to see them all."

### Choices

The walk keeps no state of its own. It moves the focused thread with `thread focus`, which the session file already saves, so after a compaction the agent still shows the right thread. What a compaction can lose is the instruction to keep walking. A saved walk flag would survive it, at the cost of a new key in every session file and a migration for the files already saved.

The walk makes one pass. A thread deferred during it stays open and is not shown again in that pass; the footer counts it, and `=/` starts a new pass from the first open thread. Coming back to deferred threads until every one is closed would leave `=//` as the only way out of a walk the user had stopped answering.

`=/` keeps the audit that `=//` runs. Without it, a walk would skip every decision raised in the conversation but never recorded.

## 0.4.0 - 2026-11-12

`set response_style` and `defaults set response_style` are gone: use `set comms` and `defaults set comms`, which take `pyramid`, `plain` and the other profiles. `set comms minimal` is gone too: use `set comms efficient`, the profile it selected. Settings saved under `response_style` still load as `communication_profile`.

### Choices

The migration that loads a saved `response_style` key stays. Files saved by 0.1.x carry the key until they are next written: a session's file when that session resumes, the defaults file when a default changes.

`minimal` gets no migration. Every release that accepted it saved `efficient` instead, so no saved file holds it.

## 0.3.0 - 2026-11-11

The `pyramid` profile renders the reply rules it was missing: a verdict first for implementation questions, reasons that do not overlap and together cover the answer, one recommendation, a table for any comparison, no preamble or closing recap, the current state rather than its history, one question at a time in an interview, and no em-dashes.

`pyramid`, `direct` and `efficient` ask the agent to define a term the reader may not know and to replace an unclear pronoun with its noun. `efficient` keeps routine replies to one to three sentences.

The STE-derived guidelines state their limits: 20 words in an instruction and 25 in a description, noun stacks of three words, paragraphs of six sentences at most, notes with no steps or risks, list mechanics, and no contractions. `direct` asks the agent to name the actor or say it is unknown, and `epistemic` separates proposals from facts and names missing evidence.

Warnings, intent signals, I-PASS, CUS and M/ETHANE use two risk levels, WARNING for irreversible harm and CAUTION for recoverable harm, and print their definitions wherever they appear. The intent signal CAUTION replaces RISK.

`delta` restates context when the reader may have lost it: after a resume, a reopened thread or a handoff. The blocker format asks for the exact error and the violated constraint.

The thread protocol adds four rules: a choice written as a sentence still gets options, a skill's own output format does not suspend threads, a reply puts settled items first and decisions last with no recap, and when a task holds decisions only the user can make, the reply carries those decisions alone.

`guidelines group list` printed every group on one line, separated by a literal `\n`; it now prints one group per line. The guideline list and the setup questions contain no em-dashes, and the first setup question asks which communication profile to use instead of how concise replies should be.

### Choices

The profile keeps the name `pyramid`. The name already is Barbara Minto's Pyramid Principle; what the profile lacked was the principle's grouping rule, which `reasons` now states. Renaming it to `minto` would have added one more alias to migrate.

Profiles carry no instruction text. Every rule a profile applies is a guideline, so `guidelines` shows all of it, and the instruction fields that were never rendered are gone.

WARNING and CAUTION are defined once, in `signals.json`, and each part of the policy that uses them prints that definition, so the places that use them cannot drift apart. They adapt ASD-STE100 7.1, where a warning guards against injury and a caution against damage to equipment, to irreversible and recoverable harm.

`define_terms` and `pronouns` sit in all three non-empty profiles, because the brevity guidelines in each cause the failures they prevent. `pronouns` cites ASD-STE100 and so joins the `ste` bundle; `define_terms` comes from Google's Technical Writing One and does not.

## 0.2.1 - 2026-11-09

In Claude Code, the `/dialogue` autocomplete hint ran past the terminal's width and was cut off, hiding most subcommands. It now lists `help`, `setup`, `settings`, `set <key> <value>` and `disable`, which fits an 80-column terminal; `/dialogue help` lists the rest.

## 0.2.0 - 2026-11-08

Communication profiles (`pyramid`, `direct`, `efficient`, `plain`) select guidelines from one catalog. Added profile and guideline inspection, SBAR/I-PASS/CAN/CUS/M-ETHANE situational modes, optional STE-inspired language, and intent/response markers. Help-first navigation and atomic three-question setup configure `comms`, `style`, and a workflow preset. Short setting aliases are supported. Guideline command hierarchy uses `guidelines list`, `guidelines group list`, `guideline enable|disable|reset ID`, and `guideline group enable|disable|reset TYPE` with backward-compatible aliases. Guidelines can be toggled individually or by purpose (structure, brevity, precision, evidence, risk, language, procedures); profiles remain optional. Twelve STE-derived guidelines can be selected by `style ste` or individually, with opt-in per-session and future-session overrides. Legacy `response_style` and `minimal` settings are migrated.

## 0.1.3 - 2026-11-08

Codex state permission errors identify the directory to authorize and explain how to configure sandbox access and restart the session.

## 0.1.2

Codex labels the startup hook as `loading dialogue settings`. Its skill picker lists Dialogue subcommands; `$dialogue:dialogue help` shows their syntax and accepted settings.

## 0.1.1

Claude Code shows subcommand syntax in the dialogue autocomplete hint. Invoke dialogue with `help`, `--help`, or `-h` to see commands and accepted settings without changing session state.

## 0.1.0

Enable response style and persistent threads explicitly in Claude Code or Codex. Each session keeps its settings across resume and compaction. The settings command shows session values, saved defaults, and explanations. Focus mode defers unrelated issues, and compact replies show a count of other open threads with commands to reveal them.

### Choices

Python's standard library handles structured records without third-party packages. Client-specific hook configurations identify the client explicitly; session IDs keep records separate. Settings and thread data live outside the plugin cache so updates retain them. Full agent-rules remains available through its installer, while its limited profile avoids overlapping conversation instructions.
