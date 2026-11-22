# Checking the README against the project

The examples below come from an audit of dotsecenv. Each check compares a
specific claim with evidence from the project.

## The environment to run in

Run the quickstart from a temporary working copy containing the version under
review. Give it fresh configuration and data directories, including any
tool-specific ones. An existing account or previous install can make a
missing step look optional. From the temporary working copy, start a shell
with isolated settings.

```shell
test_home="$(mktemp -d)"
env -i PATH="$PATH" TERM="${TERM:-dumb}" \
  HOME="$test_home" \
  XDG_CONFIG_HOME="$test_home/config" \
  XDG_DATA_HOME="$test_home/data" \
  GNUPGHOME="$test_home/gnupg" \
  bash --noprofile --norc
```

In that shell, run the documented commands in order and check the end state.
For example, store a test value and read it back. Record any step that needs
an unavailable service or prerequisite.

## The six checks

### A documented file format, against a file the tool writes

Create a real artifact and read it. dotsecenv's README showed a vault whose
line 1 was JSON with `"version": 1` and an `identities` array of pairs. A vault
made by the current code has a marker comment on line 1, the JSON on line 2,
version 2, and `identities` as an object. Three wrong claims in one code block.

Format claims rot silently: the writer reads them, the parser does not.

### The command list, against `--help`

```shell
bash "$checker" commands "$cli" "$readme"
```

Use the installed checker and the selected README paths from the audit.
Set `cli` to the project's executable. The checker reads its `--help` and
compares the command list with the commands the README names, in both
directions. If it cannot parse the help, compare the output yourself.
dotsecenv's table had 11 commands. The CLI had 14, plus four subcommands.

### The flag tables, against whatever parses the flags

`--help` covers the CLI. An installer script, a container entrypoint or a CI
action parses its own flags somewhere else, so read that file and diff it
against the table. dotsecenv's installer table was missing a flag added two
releases earlier.

### The quickstart, against a run of it

Run every command in a fresh environment as described above. Compare the
result with what the README promises. dotsecenv's quickstart told the reader
to paste a GPG fingerprint. The command prompted with a picker.

### Every recommendation, against what the tool already does

A README that tells the reader to reach for an external tool is claiming the
project has no answer of its own. Check that. dotsecenv's FAQ recommended
`gpg --full-generate-key`, and the tool ships `identity create`.

### Links and badges, against what answers

```shell
bash "$checker" links "$readme"
bash "$checker" badges "$readme"
```

The audit's `all` command includes both checks. `links` checks HTTP responses,
local paths and in-page heading anchors. `badges` compares the alt text of
badges owned by this repository with each workflow's `name:`. Five of
dotsecenv's nine badges pointed at workflows that had been renamed or deleted.
Distinguish a confirmed missing target from a server the checker could not reach.

## The claims in the draft are claims too

The self-audit is the same six checks over the text just written, and it finds
things. A draft of dotsecenv's rewrite said all eight example directories
shipped a `run.sh`. Four did.
