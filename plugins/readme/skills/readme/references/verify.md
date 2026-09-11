# Checking the README against the thing it describes

A README is a set of claims. Every one of them was true when it was written,
and the code has moved since. This is where the findings are: six defects in
dotsecenv's README, and not one of them was visible by reading.

Run the thing. Compare the output to the page.

## The environment to run in

Documented steps get run where they cannot touch the machine and cannot be
helped by it. A quickstart that passes because the author's config was already
there is a quickstart that fails for every new reader.

```shell
sandbox="$(mktemp -d)"
env -i PATH="$PATH" TERM="$TERM" \
  HOME="$sandbox" \
  XDG_CONFIG_HOME="$sandbox/config" \
  XDG_DATA_HOME="$sandbox/data" \
  GNUPGHOME="$sandbox/gnupg" \
  bash -c 'set -x; <the documented commands>'
```

Add whatever else the tool reads: `GNUPGHOME` above is for a tool that signs,
and a tool with its own `FOO_CONFIG` needs that one too. Then assert the end
state rather than the exit code. A command that stored a secret has to hand the
secret back.

## The six checks

### A documented file format, against a file the tool writes

Create a real artifact and read it. dotsecenv's README showed a vault whose
line 1 was JSON with `"version": 1` and an `identities` array of pairs. A vault
made by the current code has a marker comment on line 1, the JSON on line 2,
version 2, and `identities` as an object. Three wrong claims in one code block.

Format claims rot silently: the writer reads them, the parser does not.

### The command list, against `--help`

```shell
readme commands <cli>
```

It reads the command list out of `<cli> --help` and compares it with the
commands the README names, in both directions. dotsecenv's table had 11
commands. The CLI had 14, plus four subcommands.

### The flag tables, against whatever parses the flags

`--help` covers the CLI. An installer script, a container entrypoint or a CI
action parses its own flags somewhere else, so read that file and diff it
against the table. dotsecenv's installer table was missing a flag added two
releases earlier.

### The quickstart, against a run of it

Every command in the quickstart, in the sandbox above, in order, with nothing
skipped. This is the check that catches a step that changed shape rather than
name. dotsecenv's quickstart told the reader to paste a GPG fingerprint;
`login --help` showed the command prompts with a picker instead.

### Every recommendation, against what the tool already does

A README that tells the reader to reach for an external tool is claiming the
project has no answer of its own. Check that. dotsecenv's FAQ recommended
`gpg --full-generate-key`, and the tool ships `identity create`.

### Links and badges, against what answers

```shell
readme links
readme badges
```

`links` resolves every target: an HTTP status for a URL, a file on disk for a
relative path, a heading for an anchor. `badges` reads the workflow each badge
points at and compares the workflow's `name:` with the badge's alt text. Five
of dotsecenv's nine badges pointed at workflows that had been renamed or
deleted, and because the alt text did not match the workflow names either, a
broken badge said nothing about what it had been.

## The claims in the draft are claims too

The self-audit is the same six checks over the text just written, and it finds
things. A draft of dotsecenv's rewrite said all eight example directories
shipped a `run.sh`. Four did.
