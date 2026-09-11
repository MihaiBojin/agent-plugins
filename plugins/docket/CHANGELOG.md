# docket

Newest release first. Each says what changed, and the choices behind it.

## 0.2.1

The README says how to install the plugin, the way `decisions` and `readme`
already do.

## 0.2.0

- `/docket:scaffold` writes `<collection>/AGENTS.md`, a fourth file beside
  `docket.toml` and the two CI files. It states the rules the check enforces: a
  frozen body never changes, numbers are never reused, only `status`,
  `superseded_by` and `errata` move after the freeze, and formatters stay out
  of the directory.
- `/docket:freeze` says where `--created` comes from: the Notion page's or the
  Google Doc's creation time, the first commit on the draft's branch under the
  git backend, and the user when the backend cannot say. The helper only ever
  checked the date's shape, so a guess archived as fact.

### Choices

- The rules land as a file copied verbatim rather than prose the command
  writes. `docket.mjs` and `docket-ci.yml` are already copied that way, and a
  summary rewritten per collection is one more wording of the same rules to
  keep true.
- It is `AGENTS.md` rather than `CLAUDE.md`. The archive is read by whatever
  agent its contributors run, and the repositories that carry a `CLAUDE.md`
  point it at `AGENTS.md` already.
- Scaffold still changes nothing in a directory that is already a collection,
  so a collection made by 0.1.1 gets the file only when somebody scaffolds it
  again. Writing into an existing collection would make a command whose guard
  promises to change nothing change something.
- A minor rather than a major. Scaffold writes one more file and every other
  command behaves as it did, so nothing an existing caller depends on moved.

## 0.1.1

The first release: numbered collections, a named lifecycle, and an archive
whose frozen documents cannot change.

- `/docket:new` allocates the next number from the archive directory and opens
  the draft in the collection's backend.
- `/docket:status` reports a document's stage, backend and open comment
  threads, and verifies the hash once it is archived.
- `/docket:freeze` checks that every thread is resolved or answered, then
  exports the body, records its sha256, and commits `<collection>/<nnnn>.md`.
- `/docket:supersede` points a frozen document at its successor without
  editing either body.
- `/docket:scaffold` creates the collection's `docket.toml` and copies the
  immutability check into the archive repo.
- `docket.mjs` is the deterministic half: `next`, `freeze`, `verify`, `set`
  and `ci-check`, all local, with no network.
- Profiles are `rfc` (draft, discussion, final comment period, frozen) and
  `decision` (draft, frozen). Backends are Notion, Google Docs and git.

### Choices

- The CI check is copied into the archive repo rather than run from the
  plugin. The archive's guarantee must hold for a contributor who never heard
  of docket.
- There is no registry. The archive directory's listing is the register, the
  next number is one past the highest filename, and a withdrawn document's gap
  stays in the history.
- No preflight. A step that needs the Notion MCP, the Drive MCP or push access
  names what is missing and stops, rather than probing every backend up front.
- The mutex plugin is optional. Without it docket says plainly that numbering
  and edits are unguarded against concurrent writers, rather than refusing to
  run.
