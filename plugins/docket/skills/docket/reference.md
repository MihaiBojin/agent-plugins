# docket reference

The mechanics behind [SKILL.md](./SKILL.md): where the helper is, what it
takes, the file formats, and what the CI check enforces. Read it when
something does not go as expected - the skill covers the decisions, this
covers the details.

## Finding the helper

`docket.mjs` sits next to this file, inside the plugin.

- **Claude Code** substitutes `${CLAUDE_PLUGIN_ROOT}`, so the commands invoke
  `node "${CLAUDE_PLUGIN_ROOT}/skills/docket/docket.mjs"` and nothing has to
  be searched for.
- **Everywhere else** it is `docket.mjs` in the same directory as this file -
  the skill directory the agent loaded, such as a plugin cache under
  `~/.codex/plugins/`.
- An archive repo that ran `/docket:scaffold` carries its own copy at
  `.github/scripts/docket.mjs`, which is what its CI runs.

The helper is deterministic and local: files and local git, no network. The
backends are reached through MCP by the skill, never from here.

## The helper

| Command                        |                                                             |
| ------------------------------ | ----------------------------------------------------------- |
| `next <collection-dir>`        | The next free number, zero-padded to the collection's width |
| `freeze <collection-dir> <n>`  | Assemble `<nnnn>.md` and record the body's sha256           |
| `verify <file>`                | Recompute the hash against the frontmatter                  |
| `set <file> status <value>`    | Record a stage move                                         |
| `set <file> superseded_by <n>` | Point a frozen document at its successor                    |
| `set <file> errata <text>`     | Append one dated erratum line                               |
| `ci-check <base-ref>`          | Enforce immutability against a base revision                |

Options: `--title`, `--created <date>`, `--frozen <date>`, `--backend <ref>`
and `--body <file>` for `freeze` (`--body -` reads stdin, `--frozen` defaults
to today); `--date <date>` for `set errata` (defaults to today); `--dir
<path>` for `ci-check` (defaults to the working directory). Dates are
`YYYY-MM-DD`.

`next` is one past the highest numbered file - the directory listing is the
register, and gaps are withdrawn documents' numbers, never refilled. `freeze`
refuses a file that already exists. `set` refuses every key but the three it
names, and `set status` refuses values outside the stage set.

Exit codes: `0` success (for `verify` and `ci-check`, the rule holds), `1`
error or a failed check, `2` usage error.

## The collection

A collection is a directory in the archive repo with a `docket.toml` at its
root; the config is what makes the directory a collection, and there is no
registry anywhere else:

```toml
profile = "rfc" # rfc | decision
backend = "notion" # notion | gdocs | git
width = 4
```

Documents are `<collection>/<nnnn>.md`, numbers zero-padded to `width`. The
frozen file's git path is the document's address; hosting prettier URLs is
deliberately somebody's later problem.

## The frontmatter

`freeze` writes this schema, and nothing else writes it:

```yaml
number: 4
title: "One lock database for the organization"
status: frozen # draft | discussion | fcp | frozen | withdrawn | superseded
created: 2026-08-12
frozen: 2026-08-20
backend: notion/page/aab35f24c80846f5a0d3311a9d78f21f
content_sha256: 2f9a… # sha256 of the body, exactly as written
superseded_by: # the successor's number, set by `set`
errata: [] # dated one-liners, appended by `set`
```

`backend` is the reference to where the document was drafted: a Notion page
id as `notion/page/<id>`, a Google Doc as `gdocs/<id>`, or the archive PR's
URL for the git backend.

The body starts after one blank separator line below the closing `---`, and
`content_sha256` is the sha256 of exactly those bytes. `freeze` normalises
the body once - line endings to `\n`, leading blank lines and trailing
whitespace dropped, one final newline - and from then on the bytes are the
record. Keep formatters away from the archive directory: a rewrapped body is
a changed body, and the CI check will say so.

## The CI check

`ci-check <base-ref>` reads the diff between the base revision and the
working tree. For every changed `.md` file whose **base** version is frozen -
frontmatter `status` of `frozen` or `superseded`, with a `content_sha256` -
the change may touch the frontmatter keys `status`, `superseded_by` and
`errata`, and nothing else:

- the body must be byte-identical to the base;
- every other frontmatter key must be untouched;
- `errata` only grows - existing lines stay exactly as they are;
- `status` may only move between `frozen` and `superseded`;
- the file may not be deleted.

New files, drafts and non-docket files pass untouched.

`/docket:scaffold` installs it into the archive repo: the helper is copied to
`.github/scripts/docket.mjs` and the workflow template shipped in this plugin
becomes `.github/workflows/docket-ci.yml`, which runs the check on every pull
request against the PR's base commit. The copy is deliberate - the archive's
guarantee must not depend on any contributor having this plugin installed.

## Lock ids

When the mutex plugin is available, these are the ids; the skill decides when
to hold them:

| Operation                            | Lock id                      |
| ------------------------------------ | ---------------------------- |
| Allocating the next number           | `doc/<collection>/allocator` |
| A lifecycle transition of document n | `doc/<collection>/<nnnn>`    |
| Editing a Notion draft               | `notion/page/<id>`           |

`<nnnn>` is the zero-padded form, so the lock id matches the filename.
Without mutex nothing guards these; the skill warns and waits to be told.
