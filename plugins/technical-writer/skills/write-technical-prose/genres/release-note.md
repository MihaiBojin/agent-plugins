# Release note

The
[release plugin](https://github.com/releasetools/agent-plugins/tree/main/plugins/release#readme)
owns this genre: what goes in an entry, its category, its order and the
changelog it lands in. Its
[release-note rules](https://github.com/releasetools/agent-plugins/blob/main/plugins/release/references/release-notes.md)
say how.

Reader: somebody on the previous version, deciding whether this release
affects them.

When `release:write` or `release:prepare` loaded this skill, it holds the
entries to word. Apply the shared rules and `self_edit` to them, then go back
to that skill. Its entry shape wins where it and these rules disagree. A note
that an author declared in a `release-note` block stays as written.

For any other request for a release note or a changelog entry, use
`release:write` for one change and `release:prepare` for a release.
