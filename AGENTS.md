# Working in this repository

This is where the plugins live. Editing one is an ordinary pull request: change
the files under `plugins/<name>/`, bump its version, and the merge is the
release. Nothing is copied in from anywhere else.

A plugin that lives in another repository is listed rather than copied:
`remote-plugins.json` names its repository, the subdirectory and the release
tag, and both catalogs point there.

Two files are generated and must not be hand-edited: the catalogs.

## What is here

```text
plugins/<name>/                   A plugin. The source, not a copy of one
plugins/<name>/CHANGELOG.md       Its releases, and the choices behind them
plugins/<name>/evals/             Its eval cases, run by `claude plugin eval`
remote-plugins.json               Plugins listed from other repositories
.claude-plugin/marketplace.json   Claude Code's catalog     (generated)
.agents/plugins/marketplace.json  Codex's catalog           (generated)
scripts/validate-plugin.mjs       One plugin's own layout
scripts/validate-marketplaces.mjs What holds between the two catalogs
scripts/sync-catalogs.mjs         Writes both catalogs from plugins/
.releasetools.yaml                What this repository holds, for every releasetools tool
scripts/catalogs.mjs              What all of those agree on
__tests__/                        Jest, run by `npm test`
testbed/dialogue/                 Runs dialogue under each setting with claude -p and codex; not published
testbed/e2e/                      Runs the e2e cases with both clients; not published
Makefile                          `make e2e`
lefthook.yml, .lefthook/          Run `make e2e` before a release tag is pushed
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

A plugin from another repository takes a `git-subdir` source in both
catalogs: an https `url`, the `path` of the plugin inside that repository, and
the `ref` to clone, which is a release tag. Both clients clone it there and
read the plugin's own manifests, so its Claude Code entry carries only the
description, and its version is whatever the tag holds. Each comes from
`remote-plugins.json`:

```json
{
  "name": "worktrees",
  "url": "https://github.com/MihaiBojin/worktrees.git",
  "path": "plugin",
  "ref": "v0.7.0",
  "description": "Remove the git worktrees and branches ...",
  "category": "Developer Tools"
}
```

The validator checks the shape: an https url, a path that stays inside the
repository, a ref that is a tag or branch name, and the same three in both
catalogs. It cannot read the plugin at that ref, and CI installs only the
plugins under `plugins/`. Merge a change to `ref` once that tag exists, and
install the plugin from the branch with both clients before merging. A plugin
listed this way is versioned and released in its own repository, so neither
guard below has anything here to check.

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
the workflow: `.releasetools.yaml` names each plugin as a project, where it
keeps its version, and which changelog it owes. Projects are named rather
than matched, so a new plugin is checked once it is added to that list.

How far the version has to move follows from what the changes say they are,
which is the [releasetools conventions](https://github.com/releasetools/conventions):
`typed-change` for the subject, `bump-from-type` for the arithmetic,
`semver-versions` for the number, `changelog-per-change` for the entry, and
`breaking-says-how` for what a break owes a reader. In agent terms a new
command or skill is a `feat`, wording and fixes are a `fix`, and removing a
command or changing what one does is breaking, marked with a `!`.
`bump-from-type` turns those into a number, and nothing derives a major: a
release increments one because somebody was asked and said so.

Write the entry with `/release:write`, from the `release` plugin in the
`release-tools` marketplace. It reads the same `.releasetools.yaml`, so the
note lands in the changelog of the plugin the change is in, and it puts the
same note in the pull request as a `release-note` block, which the squash
merge carries into the commit that lands on `main`. Put the same block in the
branch commit message too, so the note is in the history whichever way the
pull request merges.

## Recording a choice

A release writes itself into `plugins/<name>/CHANGELOG.md`, newest first: what
changed, under the version carrying it, and the choices behind it under
`### Choices`.

A choice that changed nothing belongs there too. What a later change needs, and
cannot get from the diff, is the reason not to act - an alternative weighed and
dropped, a cost taken on purpose, a bug left alone because something else
already stops it.

## Rules the plugins share

The technical-writer skills use the rules in
`plugins/technical-writer/skills/write-technical-prose/SKILL.md`. Dialogue
also carries some of those rules in `plugins/dialogue/policy/guidelines.json`.
Where the two plugins declare the same rule ID, its first line must match.
The WARNING and CAUTION definitions in the prose skill also match dialogue's
`signals.json`. `__tests__/shared-rules.test.mjs` checks both.
Change the shared wording in both plugins in one pull request and bump
and write an entry for each plugin it touches.

## Evals

```shell
claude plugin eval plugins/technical-writer --case runbook --runs 1
```

Cases under `plugins/technical-writer/evals/` exercise the writing skills
and the README audit. Each grader checks one rule and
passes or fails, so the report gives a failure rate per rule. This command
runs the runbook case with and without the plugin and reports the difference.
Use `make e2e CODEX_MODEL=` for all four skill checks in Claude Code, including
the README cases that run commands in a scratch project.

A run spends money: one pass over the five cases, with Claude Fable 5.2 as
writer and judge, cost $12.93 at list price, of which $10.51 was the judge.
CI does not run it. `--max-cost-usd` sets a ceiling, and `--judge-model`
picks a cheaper judge.

## End-to-end tests

```shell
make e2e                          # technical-writer, with both clients
make e2e CODEX_MODEL=             # an empty model skips that client
```

An eval case tagged `e2e` is an end-to-end test in
`plugins/<name>/evals/e2e-<skill>/`. It holds a short request and
graders of the types `regex` and `tool_used`, which cost nothing to run. The
test passes when the client loads the skill and the reply has the skill's
shape. A new skill that writes gets a case of its own.

`testbed/e2e/e2e.py` runs the cases with both clients. Claude Code runs them
through `claude plugin eval`. Codex has no such command, so the script
installs the plugin into a throwaway `CODEX_HOME`, sends each request through
`codex exec`, and applies the same `regex` graders to the reply. A pattern
therefore has to mean the same thing in JavaScript and in Python.

A previous run of the PR description and runbook cases cost $0.48 with Claude Fable 5.2,
and 133,000 input tokens, 105,000 of them cached, with Codex on
`gpt-6-astra`. CI has no login for either client and does not run them.

`lefthook install` turns on the hook in `lefthook.yml`, once per clone. A
push that carries a release tag, `<plugin>/v<version>`, then runs that
plugin's cases first, against the plugin as the tagged commit has it. A
failure stops the push. Every other push runs nothing. `LEFTHOOK=0 git push`
skips the hook for one command. The hook is a script under `.lefthook/pre-push/`,
because lefthook skips a pre-push command when the push changes no file, and
a tag on a merged commit changes none.

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
