# This directory is a docket collection

Numbered documents, argued somewhere people can comment, then frozen here.
`docket.toml` names the profile and the backend. A `<nnnn>.md` whose
frontmatter reads `status: frozen` or `status: superseded` is a permanent
record, and `content_sha256` is the sha256 of its body exactly as written.

These rules hold whether or not you have the docket plugin installed, and a
pull request check enforces them.

- Never edit a frozen body. Not a typo, not the formatting, not because the
  author asked for it. The hash is what keeps "this decision rested on document
  4 as hashed" checkable years from now.
- A correction is one dated line appended to `errata`. A change to what the
  document argues is a new document that supersedes this one.
- Numbers are never reused. The next one is one past the highest filename, and
  a withdrawn document leaves its gap.
- After the freeze only `status`, `superseded_by` and `errata` change. Every
  other frontmatter key, and the whole body, stays as written.
- Keep formatters out of this directory. A rewrapped body is a changed body.
  Add the path to `.prettierignore`, or to whatever your formatter reads.

Superseding is a pointer rather than an edit: the successor freezes first, then
the old document gets `superseded_by` and `status: superseded`.

Make those edits with the helper, from the repository root. It refuses every
other key.

```shell
node .github/scripts/docket.mjs set <collection>/<nnnn>.md status superseded
node .github/scripts/docket.mjs set <collection>/<nnnn>.md superseded_by <n>
node .github/scripts/docket.mjs set <collection>/<nnnn>.md errata "<correction>"
node .github/scripts/docket.mjs verify <collection>/<nnnn>.md
```
