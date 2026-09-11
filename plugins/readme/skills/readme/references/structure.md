# What a README holds, and how long it gets

## The order

The [standard-readme spec](https://github.com/RichardLitt/standard-readme/blob/main/spec.md)
fixes the order. Optional sections can be dropped. The ones that stay keep
their places, and a compliant README contains no broken link.

| Section           | Status                  | What it requires                                                                                                    |
| ----------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Title             | Required                | Matches the repository, directory and package name, or carries the real name in italics beside it                   |
| Banner            | Optional                | No heading of its own, a local image, directly under the title                                                      |
| Badges            | Optional                | No heading of its own, one per line                                                                                 |
| Short description | Required                | Under 120 characters, on its own line, no `>` prefix, matching the GitHub description and the package `description` |
| Long description  | Optional                | No heading of its own                                                                                               |
| Table of contents | Required over 100 lines | Links every level-two heading, starting with the section after itself                                               |
| Security          | Optional                | Here when it has to be read early, otherwise further down                                                           |
| Background        | Optional                | Motivation, abstract dependencies, where the idea came from                                                         |
| Install           | Required, code repos    | A code block that installs it                                                                                       |
| Usage             | Required, code repos    | A code block of ordinary use, and a `CLI` subsection when there is a CLI                                            |
| Extra sections    | Optional                | Their own headings, after Usage and before API                                                                      |
| API               | Optional                | Exported functions and objects, or a pointer at a generated `API.md`                                                |
| Maintainers       | Optional                | Called `Maintainer` or `Maintainers`, with one way to reach them                                                    |
| Thanks            | Optional                | Called `Thanks`, `Credits` or `Acknowledgements`                                                                    |
| Contributing      | Required                | Where to ask, whether pull requests are accepted, what a contribution has to carry                                  |
| License           | Required, last          | The SPDX name or identifier, and the owner                                                                          |

[Make a README](https://www.makeareadme.com/) offers a shorter default for a
project that needs less: name, description, installation, usage, contributing,
licence. Its longer suggestion list adds badges, visuals, support, roadmap,
authors, and project status.

## The test

> Ideally, someone who's slightly familiar with your module should be able to
> refresh their memory without hitting "page down". As your reader continues
> through the document, they should receive a progressively greater amount of
> knowledge.

Kirrily "Skud" Robert, [perlmodstyle](https://perldoc.perl.org/perlmodstyle),
quoted by the standard-readme spec. It is the inverted pyramid: every section
serves a smaller audience than the one above it. A section that everybody needs
sitting below one that four people need is the commonest structural fault in a
long README.

Contributor material belongs in `CONTRIBUTING.md`. A reader who wants to use
the thing and a reader who wants to change it are different people, and the
second one arrives later.

## How long

| Project | Stars | Words | What else the repository ships        |
| ------- | ----- | ----- | ------------------------------------- |
| chezmoi | 21.6k | 37    | a site at chezmoi.io                  |
| sops    | 23.1k | 204   | a site at getsops.io/docs             |
| age     | 23.5k | 794   | a site at age-encryption.org, `doc/`  |
| direnv  | 15.4k | 912   | a site at direnv.net, `docs/`, `man/` |
| gum     | 24.4k | 969   | `man/`                                |
| ripgrep | 68.2k | 2621  | `GUIDE.md`, `FAQ.md`                  |
| fd      | 44.4k | 3145  | `doc/`                                |

Collected 11 September 2026 with `readme stats`, which leaves fenced code
blocks out of the count. `wc -w` over the same files returns more, from 10% for
ripgrep to 77% for gum, because it counts the code.

Nothing in that table predicts length from popularity. The range is 37 words to
3145 across projects holding 15.4k to 68.2k stars, and the busiest project in it
has the second-longest README. What separates the top two rows from the rest is
a decision: chezmoi and sops hand the reader to a documentation site and keep
almost nothing back, while fd and ripgrep keep the manual in the README even
though both ship other documents.

So the question to answer is not how long this should be. It is what is already
maintained somewhere else. That content gets a link. A copy of it goes stale on
the day the original changes, and nobody finds out, because nothing fails.

One worked example: dotsecenv went from 3327 words to 635 in
[PR #356](https://github.com/dotsecenv/dotsecenv/pull/356), and from 72 headings
five levels deep to 10 headings two levels deep, by moving what a documentation
site already held and deleting what was wrong.

## Before deleting a section

Something points at it. Run `readme anchors` for the links, and grep for
the prose references it cannot see:

```shell
grep -rn "README" --exclude-dir=.git .
```

Deleting the vault-format and exit-code sections from dotsecenv's README
orphaned two lines in its `AGENTS.md` that said a thing was "documented in
README.md". Both had to move with the content.

## Badges

A badge's alt text is what a reader sees when the image fails, which is exactly
when they need to know what it was. Make it the workflow's own `name:` field,
so a broken badge still names the thing that broke. `readme badges` compares
the two, and leaves a badge for another repository's workflow alone, since this
checkout holds no answer about it.

Five of dotsecenv's nine badges pointed at workflow files that were not there.
Every one of those is visible offline, before a single request goes out.
