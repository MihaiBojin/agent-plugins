#!/usr/bin/env bats
#
# What readme settles, with nothing reaching the network: a stub `curl`
# answers by URL, and a stub CLI answers `--help` from a file the test wrote.

bats_require_minimum_version 1.5.0

setup() {
  CHECK="${BATS_TEST_DIRNAME}/../bin/readme"
  # Resolved: on a mac $TMPDIR is a symlink into /private, and the paths the
  # script prints have been through git.
  REPO="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/proj"
  SAMPLECLI_HELP="${REPO}/help.txt"
  export CHECK REPO SAMPLECLI_HELP
  export PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"
  export HOME="$BATS_TEST_TMPDIR"
  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  mkdir -p "${REPO}/.github/workflows"
  git -C "$REPO" init -q
  # The remote is what tells a badge pointing here from one pointing at a
  # sibling repository, so a fixture without one checks no badges at all.
  git -C "$REPO" remote add origin https://github.com/o/r.git
  cd "$REPO" || exit 1
}

@test "stats leaves fenced code out of the word count" {
  cat >README.md <<'MD'
# Title

One two three four five.

```shell
alpha beta gamma delta epsilon zeta
```

## Second

six seven
MD
  run "$CHECK" stats
  [ "$status" -eq 0 ]
  [[ "$output" == "stats: 11 words, 11 lines, 2 headings (max depth 2), 1 fenced blocks" ]]
}

@test "links resolves a relative path, and says which one is not there" {
  printf 'real\n' >CONTRIBUTING.md
  cat >README.md <<'MD'
# Title

See [contributing](./CONTRIBUTING.md) and the [guide](./docs/guide.md).
MD
  run --separate-stderr "$CHECK" links
  [ "$status" -eq 0 ]
  [[ "$output" == *"./docs/guide.md is not a file beside README.md"* ]]
  [[ "$output" != *"CONTRIBUTING.md is not"* ]]
  [[ "$output" == *"readme: 1 finding(s)"* ]]
}

@test "links resolves an in-page anchor against the headings" {
  cat >README.md <<'MD'
# Title

- [Install](#install)
- [Exit codes](#exit-codes)

## Install

Words.
MD
  run --separate-stderr "$CHECK" links
  [ "$status" -eq 0 ]
  [[ "$output" == *"#exit-codes has no heading"* ]]
  [[ "$output" != *"#install has no heading"* ]]
}

@test "links reports the status a URL answers with" {
  cat >README.md <<'MD'
# Title

[here](https://example.invalid/fine), [there](https://example.invalid/gone),
and [nowhere](https://example.invalid/unreachable).
MD
  run --separate-stderr "$CHECK" links
  [ "$status" -eq 0 ]
  [[ "$output" == *"HTTP 404 https://example.invalid/gone"* ]]
  [[ "$output" == *"no answer from https://example.invalid/unreachable"* ]]
  [[ "$output" != *"/fine"* ]]
}

@test "links leaves a URL inside a fenced block alone" {
  cat >README.md <<'MD'
# Title

```shell
curl https://example.invalid/gone
```
MD
  run --separate-stderr "$CHECK" links
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 finding(s)"* ]]
  [[ "$stderr" == *"links: 0 checked"* ]]
}

@test "badges name the workflow they point at" {
  printf 'name: Build and test\non: push\n' >.github/workflows/ci.yml
  cat >README.md <<'MD'
# Title

[![Build and test](https://github.com/o/r/actions/workflows/ci.yml/badge.svg)](https://github.com/o/r/actions)
[![Release](https://github.com/o/r/actions/workflows/release.yml/badge.svg)](https://github.com/o/r/actions)
MD
  run --separate-stderr "$CHECK" badges
  [ "$status" -eq 0 ]
  [[ "$output" == *"points at .github/workflows/release.yml, which is not here"* ]]
  [[ "$output" == *"readme: 1 finding(s)"* ]]
}

@test "badges catch alt text that does not match the workflow name" {
  printf 'name: Validate\non: push\n' >.github/workflows/ci.yml
  cat >README.md <<'MD'
# Title

![Build](https://github.com/o/r/actions/workflows/ci.yml/badge.svg)
MD
  run --separate-stderr "$CHECK" badges
  [ "$status" -eq 0 ]
  [[ "$output" == *'"Build" is the alt text'* ]]
  [[ "$output" == *'is named "Validate"'* ]]
}

@test "badges for another repository are left alone" {
  printf 'name: Validate\non: push\n' >.github/workflows/ci.yml
  cat >README.md <<'MD'
# Title

![Validate](https://github.com/o/r/actions/workflows/ci.yml/badge.svg)
![Homebrew](https://github.com/o/homebrew-tap/actions/workflows/post-release.yml/badge.svg)
MD
  run --separate-stderr "$CHECK" badges
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 finding(s)"* ]]
  [[ "$stderr" == *"1 checked, 1 pointing at another repository"* ]]
}

@test "badges need a remote to say which of them point here" {
  git remote remove origin
  printf '# Title\n\n![Nope](https://github.com/o/r/actions/workflows/gone.yml/badge.svg)\n' >README.md
  run --separate-stderr "$CHECK" badges
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 finding(s)"* ]]
  [[ "$stderr" == *"no GitHub remote here"* ]]
}

@test "anchors find a pointer into a heading that was deleted" {
  cat >README.md <<'MD'
# Title

## Install

Words.
MD
  cat >AGENTS.md <<'MD'
The vault format is documented in [README.md#vault-format](README.md#vault-format),
and installing is in [README.md#install](README.md#install).
MD
  run --separate-stderr "$CHECK" anchors
  [ "$status" -eq 0 ]
  [[ "$output" == *"wants #vault-format, and README.md has no such heading"* ]]
  [[ "$output" != *"#install, and README.md"* ]]
  [[ "$output" == *"readme: 1 finding(s)"* ]]
}

@test "anchors leave a pointer at another README alone" {
  mkdir -p sub
  printf '# Title\n\n## Install\n' >README.md
  printf '# Sub\n\n## Usage\n' >sub/README.md
  printf 'See [README.md#usage](README.md#usage).\n' >sub/NOTES.md
  run --separate-stderr "$CHECK" anchors
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 finding(s)"* ]]
  [[ "$stderr" == *"anchors: 0 checked"* ]]

  run --separate-stderr "$CHECK" anchors sub/README.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 finding(s)"* ]]
  [[ "$stderr" == *"anchors: 1 checked"* ]]
}

@test "commands compare the CLI's help with the README, both ways" {
  cat >help.txt <<'HELP'
samplecli - does things

USAGE
  samplecli <command>

COMMANDS
  store      Store a thing
  fetch      Fetch a thing
  doctor     Check the setup
HELP
  cat >README.md <<'MD'
# samplecli

Run `samplecli store` to store one and `samplecli fetch` to read it back.
Run `samplecli legacy` for the old way.
MD
  run --separate-stderr "$CHECK" commands samplecli
  [ "$status" -eq 0 ]
  [[ "$output" == *"samplecli doctor is in --help and not in README.md"* ]]
  [[ "$output" == *"README.md names samplecli legacy, and --help does not"* ]]
  [[ "$output" != *"samplecli store is in --help"* ]]
  [[ "$stderr" == *"3 read from samplecli --help"* ]]
}

@test "commands say so when the help lists nothing they can read" {
  printf 'samplecli, a tool with prose for help\n' >help.txt
  printf '# samplecli\n\nWords.\n' >README.md
  run --separate-stderr "$CHECK" commands samplecli
  [ "$status" -eq 0 ]
  [[ "$output" == *"lists no commands this can read"* ]]
}

@test "all runs every check over the default file and counts once" {
  printf 'name: Validate\non: push\n' >.github/workflows/ci.yml
  cat >README.md <<'MD'
# Title

![Build](https://github.com/o/r/actions/workflows/ci.yml/badge.svg)

A [dead link](https://example.invalid/gone) and a [dead file](./nope.md).
MD
  run --separate-stderr "$CHECK" all
  [ "$status" -eq 0 ]
  [[ "$output" == stats:* ]]
  [[ "$output" == *"HTTP 404"* ]]
  [[ "$output" == *"./nope.md is not a file"* ]]
  [[ "$output" == *'is named "Validate"'* ]]
  [[ "$output" == *"readme: 3 finding(s)"* ]]
}

@test "a file that is not there fails, and says which" {
  run "$CHECK" stats MISSING.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such file: MISSING.md"* ]]
}

@test "an unknown command prints the usage and fails" {
  run "$CHECK" wat
  [ "$status" -eq 1 ]
  [[ "$output" == *"USAGE"* ]]
}
