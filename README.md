# MihaiBojin agent plugins

Mihai Bojin's personal plugin marketplace, serving Claude Code and Codex from
one catalog each. What lives here is personal and process tooling; release
tooling stays in
[releasetools/agent-plugins](https://github.com/releasetools/agent-plugins),
and the two never cross-list.

Add the marketplace once. Everything after that is installing plugins from it.

## Claude Code

```shell
claude plugin marketplace add MihaiBojin/agent-plugins
claude plugin install <name>@mihaibojin
```

Both steps work as `/plugin marketplace add` and `/plugin install` inside a
session.

## Codex

```shell
codex plugin marketplace add MihaiBojin/agent-plugins
codex plugin add <name>@mihaibojin
```

## What is published

| Plugin                            | What it does                                                                           |
| --------------------------------- | -------------------------------------------------------------------------------------- |
| [docket](./plugins/docket#readme) | Numbered document collections, argued through review, frozen into an immutable archive |
| [origin](./plugins/origin#readme) | Git worktrees, pull request merges, and rebasing onto the head branch                  |

Each plugin lives in `plugins/<name>/` in this repository: the source, not a
copy of one. Editing a plugin is an ordinary pull request, and the merge is the
release. See [AGENTS.md](./AGENTS.md) for how that works.

## Development

```shell
npm run check    # format, shellcheck, both test suites, then both validators
```

A plugin written in shell brings its own tests: `npm run test:shell` runs
`bats` against throwaway repositories with a local bare `origin` and stubbed
`gh` and `glab` on PATH, and `npm run lint:shell` runs `shellcheck` through
every sourced file. Both run in CI on Linux and on macOS, because macOS ships
bash 3.2 and that is the one these are written for.

The layout and the validation machinery are ported from
[releasetools/agent-plugins](https://github.com/releasetools/agent-plugins),
where they earned their keep first: `validate-plugin.mjs` checks one plugin's
own layout, `validate-marketplaces.mjs` checks what holds between the two
catalogs, `sync-catalogs.mjs` rewrites both catalogs from `plugins/`, and
`check-version-bump.mjs` insists that a changed plugin says so in its version.

Two pieces did not make the trip. `install-agent-skills.mjs` - the copy-based
installs for agents that read no manifest (Hermes, Gemini, Antigravity) - only
served the arrangement where a plugin's source repo seeds those agents from a
global install; it can come back when a plugin here wants those installs. The
TypeScript test setup went with it: it existed for tests inherited from a
TypeScript repository, and everything here is plain ESM, so there is no
`typecheck` to run.
