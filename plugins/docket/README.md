# docket

Docket gives a team a predictable way to turn a working document into a
permanent record.

It keeps documents in numbered collections, lets people discuss them where
they already work, and freezes the final version as an immutable, hashed
Markdown snapshot in an archive repo. RFCs are the first built-in workflow,
but they are not the only thing docket can manage. Shorter decisions, policy
proposals, and other documents that need a clear history fit too.

The name comes from a docket's two meanings: a numbered register of matters
under review, and a list of what belongs in a package.

## Where the idea comes from

**Oxide RFDs** provide the basic shape: a numbered series of engineering
documents, stable addresses, and a named lifecycle from early discussion to
a committed decision. Docket also borrows the nice recursive habit of putting
the process's own description through the process first.

**IETF RFCs** provide the rule for finished documents: once published, the
text does not change. Corrections are recorded as errata, while a substantive
change becomes a new document that supersedes the old one. Docket follows the
same rule after a document is frozen.

**Rust's final comment period** inspires the `fcp` stage in the `rfc` profile.
During this window, edits should only address review comments. Any unresolved
dissent is written into the document before it freezes, rather than quietly
disappearing from the record.

**Architecture decision records** provide the smaller form: context, a
decision, its consequences, and a status that can eventually become
superseded. Docket's `decision` profile uses that simpler draft-to-frozen path
for choices that do not need a full RFC cycle.

## How it works

A document starts wherever your team can comment on it: Notion, Google Docs,
or a pull request. It then moves through a small set of named stages. When the
discussion is done, docket exports the body to Markdown, hashes it, and writes
it to the archive as `<collection>/<nnnn>.md`.

The file's frontmatter records its number, dates, source reference, and
`content_sha256`. The archive directory itself is the register: each new
document takes the number after the highest existing filename. Numbers are
never reused, and any gaps remain part of the history.

Docket also scaffolds a CI check for the archive repo. On every pull request,
it makes sure a frozen document's body has not changed. Only `status`,
`superseded_by`, and `errata` may be updated afterward.

The same scaffold writes `AGENTS.md` into the collection, stating those rules
where the documents are. The check reports a broken rule; the file is what
tells somebody before they break it.

If the [mutex plugin](https://github.com/releasetools/mutex) is available,
docket uses `doc/<collection>/allocator` while assigning numbers and
`doc/<collection>/<nnnn>` during lifecycle changes. Without it, docket warns
that another writer could make a conflicting change and waits for you to
decide whether to continue.

## Profiles

| Profile    | Stages                                                                         |
| ---------- | ------------------------------------------------------------------------------ |
| `rfc`      | draft, discussion, fcp, frozen - plus withdrawn, and superseded after the fact |
| `decision` | draft, frozen                                                                  |

## Backends

Each collection chooses its drafting and discussion backend in `docket.toml`.
Docket does not probe every backend up front. If the current step needs a
service it cannot reach, it tells you which capability is missing and stops
there.

| Backend     | Discussion               | Freeze enforcement                                           |
| ----------- | ------------------------ | ------------------------------------------------------------ |
| Notion      | page comments, via MCP   | `is_locked: true` on the page                                |
| Google Docs | doc comments, via MCP    | Drive contentRestrictions read-only; verify when implemented |
| git         | a PR on the archive repo | the merge is the freeze; nothing external                    |

## Commands

| Command                                             | What it does                                       |
| --------------------------------------------------- | -------------------------------------------------- |
| `/docket:new <collection> "<title>"`                | Assign the next number and open a draft            |
| `/docket:status <collection> <n>`                   | Show the stage, backend, and open review threads   |
| `/docket:freeze <collection> <n>`                   | Run the final checks and export the frozen record  |
| `/docket:supersede <collection> <old> <new>`        | Link the old document to its replacement           |
| `/docket:scaffold <collection> [profile] [backend]` | Create the collection, its rules, and the CI check |

Docket handles the mechanics, but it does not pretend the important calls are
mechanical. Deciding whether a thread is truly resolved, how to work with the
available backend, or whether a change deserves a new document still requires
judgment. The guidance for those calls lives in
[the skill](./skills/docket/SKILL.md), with implementation details in
[the reference](./skills/docket/reference.md).
