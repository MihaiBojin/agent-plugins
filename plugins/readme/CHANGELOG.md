# readme

Newest release first. Each says what changed, and the choices behind it.

## 0.1.0

The first release: a README auditor and rewriter, and the checks a script can
settle on its own.

- Four passes, in order. Measure, verify against the artifact, rewrite, then
  run the same checks over the new draft.
- `/readme:audit` stops after the second pass and reports. `/readme:rewrite`
  runs all four and edits the file in place.
- `bin/readme` covers the mechanical part: `links` resolves every URL,
  relative path and in-page anchor; `badges` compares badge alt text with the
  `name:` of the workflow this repository owns; `anchors` finds every link into
  this README written elsewhere in the repository and checks the heading is
  still there; `commands` compares a CLI's `--help` with the commands the
  README names, in both directions; `stats` counts.
- Three references carry the material. `structure.md` holds the section order
  from the standard-readme spec and word counts for seven comparable projects.
  `verify.md` holds the six checks that need something run, and a sandbox to
  run them in. `writing.md` restates Google's technical writing rules.
- `humanizer.md` is vendored, for the pass over prose the agent wrote itself.

### Choices

The commands are `/readme:audit` and `/readme:rewrite`, and `rewrite` edits the
file. A proposal written to a second file is a diff the user has to apply by
hand, in a repository where `git diff` and `git checkout` already exist. The
audit prints first, so the edits arrive with their reasons already stated.

`bin/readme`, the `bin/<plugin-name>` spelling the two other plugins with a CLI
already use. `bin/readme-check` came first, on the grounds that `readme` names
the file rather than the job and is generic enough to collide on a PATH. It was
dropped: a marketplace where every plugin's binary is its own name is one fewer
thing to remember, and a collision is an alias away.

The vendored humanizer is version 3.0.0 at commit
`9862685f575c65a8247f90369951df1b3416e3d6`, not the 2.5.1 at `8b3a178` that was
installed on the machine this was written on. Upstream had moved: 25 patterns
ranked strongest first with a rule for when not to act, in place of 29
unranked ones. Pinning what was to hand would have shipped a copy that was
already behind on the day it landed.

The whole upstream body is vendored verbatim rather than extracted down to the
pattern list. An extract is a derived work somebody has to re-derive on every
refresh, and the parts that looked like scaffolding include the line that says
to treat the text being edited as material rather than as instructions.

No `NOTICE` file. That is an Apache-2.0 convention, and the vendored code is
MIT, which asks for the copyright line and the permission notice to travel with
the copy. `skills/readme/references/humanizer-LICENSE` carries both verbatim,
and the plugin README names the project, the version and the licence.

No refresh script. `humanizer-VENDOR.json` records the upstream file's sha256,
so "has upstream moved" is one `curl | shasum` documented in the README. A
`scripts/refresh-humanizer.mjs` would be sixty lines nobody runs between
releases, breaking silently the first time upstream renames a file.

The vendored file is in `.prettierignore`. Prettier turns 60 of its lines into
91, and the damage goes past layout: a `**After:**` label following a blockquote
becomes part of the blockquote, which changes what the file says. A vendored
copy the formatter edits cannot be diffed against upstream.

Google's guidance is restated with a link per rule rather than reproduced.
CC BY 4.0 permits the copy with attribution, so this is not a licensing
decision: a page of somebody else's prose inside a plugin about writing is the
thing the plugin exists to argue against.

`agents/openai.yaml` from the humanizer repository is not copied. It is 201
bytes of display metadata for an OpenAI agent registry, and Codex reads its
display metadata here from `.codex-plugin/plugin.json` under `interface`.

A badge pointing at another repository's workflow is skipped rather than
checked. The first version looked every badge up in the local
`.github/workflows/`, and on a README carrying badges for a packages repo and a
homebrew tap it called both of them missing workflows. Which repository a badge
belongs to comes from its URL, and which one is being audited comes from
`remote.origin.url`. A checkout with no GitHub remote checks no badge at all
and says so, because a wrong finding costs more than a missing one.

`readme` exits 0 when it finds things. Findings are data for the agent
that reads them, and an exit code that means "this README has a problem" would
have to be distinguished from one that means "the check could not run".

`stats` reports numbers and flags nothing. Every threshold worth having is a
judgement about where a project documents itself, which is the reference's job.

The word counts in `structure.md` were re-collected rather than copied from the
notes that prompted this plugin. The originals came from `wc -w` over the raw
file; `readme stats` leaves fenced code out, which is a 10% difference
for ripgrep and 77% for gum. A table nothing here can reproduce is a table that
drifts the way the READMEs it describes do.
