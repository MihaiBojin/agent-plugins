# readme

Check a README's claims by running the thing it describes, then rewrite it
around what is true.

A README is a set of claims about a repository, and every one of them was true
when it was written. Reading it tells you what somebody believed. Running it
tells you what is left.

## Four passes

1. Measure. Words, headings, depth, and what the repository documents
   elsewhere. Comparable projects range from 37 words to 3145, and none of that
   tracks how large the project is.
2. Verify. Six checks that each need something run, among them the CLI's
   `--help` against the documented command list, a real artifact against any
   documented file format, and the quickstart start to finish somewhere the
   machine cannot help it. This is where the findings are.
3. Rewrite. Delete what is false before reordering anything, link what is
   maintained elsewhere instead of copying it, and move whatever pointed at a
   section you removed.
4. Self-audit. The same checks over the draft written minutes ago, then a pass
   for the patterns that make prose read as machine-written.

| Command           | What it does                                                |
| ----------------- | ----------------------------------------------------------- |
| `/readme:audit`   | Passes 1 and 2, reported. Changes nothing                   |
| `/readme:rewrite` | All four, editing the file in place after showing the audit |

Both take an optional path and default to `README.md` in the working
directory.

## What the script settles

`bin/readme` answers the questions that have answers. Judgement stays in
the skill.

```shell
readme all             # stats, links, badges and anchors
readme links           # URLs to a status, relative paths to a file, anchors to a heading
readme badges          # badge alt text against the workflow it names
readme anchors         # every link into this README written elsewhere
readme commands <cli>  # the CLI's --help against the commands the README names
readme stats           # words, lines, headings, depth, fenced blocks
```

Findings go to stdout one per line, counts to stderr. The exit status says
whether the run worked, not whether it found anything, because a finding is
data for the agent reading it.

## Credit

The self-audit patterns are vendored from
[blader/humanizer](https://github.com/blader/humanizer), version 3.0.0 at
commit `9862685f575c65a8247f90369951df1b3416e3d6`, MIT, Copyright (c) 2025 Siqi
Chen. The notice is at
[skills/readme/references/humanizer-LICENSE](skills/readme/references/humanizer-LICENSE)
and the pin at
[humanizer-VENDOR.json](skills/readme/references/humanizer-VENDOR.json). Those
patterns come in turn from Wikipedia's
[Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing),
CC BY-SA 4.0, maintained by WikiProject AI Cleanup.

To find out whether the vendored copy is behind:

```shell
curl -sSL https://raw.githubusercontent.com/blader/humanizer/main/SKILL.md |
  shasum -a 256
```

Compare that against `sha256` in `humanizer-VENDOR.json`. A different hash
means re-vendoring the body below the front matter and updating the pin.

The prose rules are restated, not reproduced, from Google's
[Technical Writing One](https://developers.google.com/tech-writing/one) and
[Two](https://developers.google.com/tech-writing/two), CC BY 4.0. Structure
comes from the
[standard-readme spec](https://github.com/RichardLitt/standard-readme/blob/main/spec.md)
and [Make a README](https://www.makeareadme.com/).

## Install

```
/plugin marketplace add MihaiBojin/agent-plugins
/plugin install readme@mihaibojin
```
