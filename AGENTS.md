# Working in this repository

This is where the plugins live. Editing one is an ordinary pull request: change
the files under `plugins/<name>/`, bump its version, and the merge is the
release. Nothing is copied in from anywhere else.

Two files are generated and must not be hand-edited: the catalogs.

## What is here

```text
plugins/<name>/                   A plugin. The source, not a copy of one
plugins/<name>/CHANGELOG.md       Its releases, and the choices behind them
.claude-plugin/marketplace.json   Claude Code's catalog     (generated)
.agents/plugins/marketplace.json  Codex's catalog           (generated)
scripts/validate-plugin.mjs       One plugin's own layout
scripts/validate-marketplaces.mjs What holds between the two catalogs
scripts/sync-catalogs.mjs         Writes both catalogs from plugins/
.releasetools.yaml                What this repository holds, for every releasetools tool
scripts/catalogs.mjs              What all of those agree on
__tests__/                        Jest, run by `npm test`
```

## The two catalogs

Both name the marketplace `mihaibojin`, so `<name>@mihaibojin` means the same
thing in either client. They describe the same plugins in the same order, and
each keeps its own client's schema:

- **Claude Code** takes a relative `source` of `./plugins/<name>`, the plugin's
  version, and the descriptive metadata it shows - description, author,
  homepage, licence, keywords. All of it comes from the plugin's
  `.claude-plugin/plugin.json`.
- **Codex** takes a local source object, `policy.installation: AVAILABLE`,
  `policy.authentication: ON_INSTALL`, and a category. It keeps its display
  metadata in the plugin's own manifest under `interface`, so the catalog entry
  carries only the category, which comes from there too.

Codex has no other kind of source. Its catalog resolves a plugin as a path
inside the marketplace it cloned, so a plugin cannot be a pointer at another
repository - which is why the plugins are here rather than referenced.

Neither client validates the other's file, so a marketplace whose two halves
disagree installs different things depending on which agent you asked. That is
what `validate-marketplaces.mjs` exists to catch, along with a source escaping
`plugins/`, a catalog version that is not the plugin's, a symlink or a secret in
a published tree, and a catalog somebody reformatted by hand.

## Changing a plugin

```shell
npm run check          # lint, tests, then both validators
npm run sync           # rewrite the catalogs from plugins/
```

**Bump the version in both manifests, and write the entry.** This is the rule
with no second chance: a client that already installed 0.1.0 compares versions
to decide whether an update exists, so shipping a fix under the same number
means nobody receives it, quietly, on every machine that already had it. A fix
shipped with nothing written down loses the reasoning while somebody still
remembers it.

Two checks on every pull request enforce that, both from
[releasetools/actions](https://github.com/releasetools/actions):
`versions-guard` asks whether the version moved far enough for what changed,
and `changelog-guard` asks whether the plugin's `CHANGELOG.md` carries a
section for the version it now declares. Neither takes any configuration from
the workflow: `.releasetools.yaml` says that each directory under `plugins/`
is a project, where it keeps its version, and which changelog it owes.

How far the version has to move follows from what the changes say they are,
which is the [releasetools conventions](https://github.com/releasetools/conventions):
`typed-change` for the subject, `bump-from-type` for the arithmetic,
`semver-versions` for the number, `changelog-per-change` for the entry, and
`breaking-says-how` for what a break owes a reader. In agent terms a new
command or skill is a minor, wording and fixes are a patch, and removing a
command or changing what one does is a major.

Write the entry with `/release-notes:write`, from the `release-notes` plugin
in the `release-tools` marketplace. It reads the same `.releasetools.yaml`, so
the note lands in the changelog of the plugin the change is in, and it puts
the same note in the pull request as a `release-note` block, which
`origin merge` carries into the commit that lands on `main`.

## Recording a choice

A release writes itself into `plugins/<name>/CHANGELOG.md`, newest first: what
changed, under the version carrying it, and the choices behind it under
`### Choices`.

A choice that changed nothing belongs there too. What a later change needs, and
cannot get from the diff, is the reason not to act - an alternative weighed and
dropped, a cost taken on purpose, a bug left alone because something else
already stops it.

## Before committing

```shell
npm run check
claude plugin validate --strict .
```

While the catalog is empty, drop `--strict`: it promotes warnings to errors,
and an empty marketplace warns by definition. Strictness arrives with the
first plugin, and the workflow makes the same distinction.

`.github/workflows/validate.yml` runs those, then installs every published
plugin with both clients out of the checkout. `main` requires the `validated`
job, which is one check name that stays true as the catalog grows.
