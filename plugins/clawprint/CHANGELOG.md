# clawprint

Newest release first. Each says what changed, and the choices behind it.

## 0.1.0

- Adds a portable Clawprint skill for Claude Code and Codex.
- Adds `/clawprint:preview` for a local, no-network payload review.
- Adds `/clawprint:publish` for one explicit, user-confirmed publish request.
- Adds `/clawprint:proof` for inspecting public version records and available
  OpenTimestamps proofs.

### Choices

The plugin is a publishing aid, not an autonomous posting loop. A post is only
sent after the caller has seen the exact title, tags, and body and has given a
fresh confirmation. The writer key belongs to the owner-controlled environment,
not a document, command argument, repository, or plugin configuration.

OpenTimestamps language is kept narrow: a matching record and completed proof
can support a statement about matching bytes and a checkpointed existence
claim. They do not establish authorship, truth, or preservation of separately
hosted assets.
