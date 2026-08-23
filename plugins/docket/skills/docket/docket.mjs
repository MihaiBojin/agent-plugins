/*
 * Copyright (c) 2026 Mihai Bojin
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";

/**
 * The half of the docket skill that has to be deterministic.
 *
 * An agent can reason about a discussion, but four things cannot be left to
 * reasoning:
 *
 * - **The next number.** Two writers guessing at it allocate the same one; a
 *   single rule reading the same directory cannot. The archive listing is the
 *   register: the next number is one past the highest filename, and gaps stay
 *   gaps, because numbers are never reused.
 * - **The frozen file's shape.** The frontmatter schema and the byte-exact
 *   body are what the recorded hash and the CI check stand on, so the file is
 *   assembled here, one way, rather than typed out slightly differently each
 *   time.
 * - **What may change after the freeze.** `set` can write exactly three
 *   things - `status`, `superseded_by`, and one more erratum line - and
 *   refuses everything else, so an agent cannot be talked into "just fixing"
 *   a frozen body.
 * - **The check itself.** `ci-check` re-reads the same rule from a git diff,
 *   which is what makes the promise hold for writers who never load this
 *   plugin at all.
 *
 * Everything here is local: files and local git. No network, no backend - the
 * backends (Notion, Google Docs, the PR itself) are the skill's to reason
 * about, through whatever MCP the session has.
 */

const EXIT_OK = 0;
const EXIT_ERROR = 1;
const EXIT_USAGE = 2;

/** How wide the numbers are when the collection's config does not say. */
export const DEFAULT_WIDTH = 4;

/** Every stage any profile uses. `set status` refuses anything else. */
export const STATUSES = [
  "draft",
  "discussion",
  "fcp",
  "frozen",
  "withdrawn",
  "superseded",
];

/**
 * The statuses that mean the body is settled.
 *
 * `superseded` is in the list because superseding points at a successor; it
 * does not thaw the text. A frozen document stays frozen under every later
 * status it can reach.
 */
export const FROZEN_STATUSES = ["frozen", "superseded"];

/** The only frontmatter keys that stay writable after the freeze. */
export const MUTABLE_KEYS = ["status", "superseded_by", "errata"];

const CONFIG_FILENAME = "docket.toml";

// ---------------------------------------------------------------------------
// The collection's config
// ---------------------------------------------------------------------------

/**
 * Reads `docket.toml` at the collection directory's root.
 *
 * A deliberately small reader for three keys - `profile`, `backend`,
 * `width` - in `key = "value"` form. The file is what makes a directory a
 * collection: without it, `next` refuses rather than allocating a number in
 * whatever directory a typo pointed at.
 */
export function readCollectionConfig(directory) {
  let text;
  try {
    text = fs.readFileSync(path.join(directory, CONFIG_FILENAME), "utf8");
  } catch {
    return null;
  }

  const config = { profile: null, backend: null, width: DEFAULT_WIDTH };
  for (const line of text.split(/\r?\n/)) {
    const stripped = line.split("#")[0].trim();
    const setting = /^([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(.+)$/.exec(stripped);
    if (!setting) {
      continue;
    }
    const [, key, raw] = setting;
    const value =
      raw.startsWith('"') && raw.endsWith('"') ? raw.slice(1, -1) : raw;
    if (key === "profile") {
      config.profile = value;
    } else if (key === "backend") {
      config.backend = value;
    } else if (key === "width") {
      if (!/^[1-9]\d*$/.test(value)) {
        throw new Error(`width in ${CONFIG_FILENAME} must be a whole number`);
      }
      config.width = Number(value);
    }
  }
  return config;
}

// ---------------------------------------------------------------------------
// The file format
// ---------------------------------------------------------------------------

/**
 * Splits a document into its frontmatter lines and its raw body.
 *
 * The body is kept as the exact bytes after the closing `---` line, because
 * byte-identical is the promise the CI check enforces: `set` edits a
 * frontmatter line and writes those bytes back untouched.
 */
export function parseDocument(text) {
  const lines = text.split("\n");
  if (lines[0] !== "---") {
    return null;
  }
  const close = lines.indexOf("---", 1);
  if (close === -1) {
    return null;
  }
  return {
    frontmatter: lines.slice(1, close),
    body: lines.slice(close + 1).join("\n"),
  };
}

/**
 * Frontmatter as ordered entries: a value after the colon, and any `- ` lines
 * that follow as the key's items. Enough for the schema this file writes, and
 * nothing more.
 */
export function parseFrontmatter(lines) {
  const entries = [];
  for (const line of lines) {
    const key = /^([A-Za-z_][A-Za-z0-9_]*):\s?(.*)$/.exec(line);
    if (key) {
      entries.push({ key: key[1], value: key[2].trim(), items: [] });
      continue;
    }
    const item = /^\s+-\s+(.*)$/.exec(line);
    if (item && entries.length > 0) {
      entries[entries.length - 1].items.push(item[1].trim());
    }
  }
  return entries;
}

export function frontmatterEntry(lines, key) {
  return parseFrontmatter(lines).find((entry) => entry.key === key) ?? null;
}

/**
 * The exact body the recorded hash names.
 *
 * The freeze writes one blank separator line between the frontmatter and the
 * body; everything after it is the hashed content. Byte-exact on purpose: the
 * hash is what keeps "decision D rested on document N as hashed" checkable
 * forever, so nothing here is normalised away at read time.
 */
export function hashedBody(rawBody) {
  return rawBody.startsWith("\n") ? rawBody.slice(1) : rawBody;
}

export function sha256(text) {
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

/**
 * What the freeze does to a body before hashing it: line endings to `\n`,
 * leading blank lines dropped, trailing whitespace dropped, one final
 * newline. Applied once, at assembly - after that the bytes are the record.
 */
export function normalizeBody(text) {
  const unix = text.replace(/\r\n/g, "\n");
  const trimmed = unix.replace(/^\n+/, "").replace(/[\s]+$/, "");
  return trimmed === "" ? "" : `${trimmed}\n`;
}

function quote(text) {
  return `"${text.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function readDate(value, name) {
  if (value === undefined) {
    return undefined;
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`--${name} must be a date in YYYY-MM-DD form`);
  }
  return value;
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

function write(stream, text) {
  stream.write(text.endsWith("\n") ? text : `${text}\n`);
}

/**
 * The next free number, as the filename will spell it.
 *
 * One past the highest numbered file, never the first gap: a gap is a
 * withdrawn document's number, burned on purpose. The caller is expected to
 * hold `doc/<collection>/allocator` while acting on the answer - this only
 * reads a directory, and two unguarded readers get the same number.
 */
export function commandNext(directory, options = {}) {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;

  const config = readCollectionConfig(directory);
  if (!config) {
    write(
      stderr,
      `docket: '${directory}' is not a collection: it has no ${CONFIG_FILENAME}`,
    );
    return EXIT_ERROR;
  }

  let entries;
  try {
    entries = fs.readdirSync(directory);
  } catch (error) {
    write(stderr, `docket: cannot read '${directory}': ${error.message}`);
    return EXIT_ERROR;
  }

  const highest = entries
    .map((entry) => /^(\d+)\.md$/.exec(entry)?.[1])
    .filter(Boolean)
    .reduce((max, digits) => Math.max(max, Number(digits)), 0);

  write(stdout, String(highest + 1).padStart(config.width, "0"));
  return EXIT_OK;
}

/**
 * Assembles the frozen snapshot: frontmatter, one blank line, the body.
 *
 * The body is normalised once, hashed, and written; from here on the CI check
 * holds it byte-identical. An existing file is refused rather than replaced,
 * because a number that is already a file was allocated by somebody - never
 * reused, even by mistake.
 */
export function commandFreeze(directory, number, options = {}) {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;

  const config = readCollectionConfig(directory);
  if (!config) {
    write(
      stderr,
      `docket: '${directory}' is not a collection: it has no ${CONFIG_FILENAME}`,
    );
    return EXIT_ERROR;
  }
  if (!/^\d+$/.test(number ?? "")) {
    write(stderr, `docket: '${number}' is not a document number`);
    return EXIT_USAGE;
  }
  for (const [name, value] of [
    ["title", options.title],
    ["created", options.created],
    ["backend", options.backend],
    ["body", options.body],
  ]) {
    if (!value) {
      write(stderr, `docket: freeze needs --${name}`);
      return EXIT_USAGE;
    }
  }
  if (/[\r\n]/.test(options.title)) {
    write(stderr, "docket: --title must be a single line");
    return EXIT_USAGE;
  }

  let raw;
  try {
    raw = fs.readFileSync(options.body === "-" ? 0 : options.body, "utf8");
  } catch (error) {
    write(stderr, `docket: cannot read --body: ${error.message}`);
    return EXIT_ERROR;
  }
  const body = normalizeBody(raw);
  if (body === "") {
    write(stderr, "docket: the body is empty; nothing to freeze");
    return EXIT_ERROR;
  }

  const padded = String(Number(number)).padStart(config.width, "0");
  const file = path.join(directory, `${padded}.md`);
  if (fs.existsSync(file)) {
    write(
      stderr,
      `docket: ${file} already exists; numbers are never reused, so this one is taken`,
    );
    return EXIT_ERROR;
  }

  const hash = sha256(body);
  const frontmatter = [
    `number: ${Number(number)}`,
    `title: ${quote(options.title)}`,
    "status: frozen",
    `created: ${options.created}`,
    `frozen: ${options.frozen ?? today()}`,
    `backend: ${options.backend}`,
    `content_sha256: ${hash}`,
    "superseded_by:",
    "errata: []",
  ];
  fs.writeFileSync(file, `---\n${frontmatter.join("\n")}\n---\n\n${body}`);

  write(
    stdout,
    `Wrote ${file}\n` +
      `  status: frozen\n` +
      `  content_sha256: ${hash}\n` +
      `  The body is now the record: corrections are errata lines, substantive\n` +
      `  change is a new document that supersedes this one.`,
  );
  return EXIT_OK;
}

/** Recomputes the body's hash and compares it to the frontmatter's record. */
export function commandVerify(file, options = {}) {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;

  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (error) {
    write(stderr, `docket: cannot read '${file}': ${error.message}`);
    return EXIT_ERROR;
  }
  const document = parseDocument(text);
  if (!document) {
    write(stderr, `docket: '${file}' has no frontmatter`);
    return EXIT_ERROR;
  }
  const recorded = frontmatterEntry(document.frontmatter, "content_sha256");
  if (!recorded?.value) {
    write(stderr, `docket: '${file}' records no content_sha256`);
    return EXIT_ERROR;
  }

  const actual = sha256(hashedBody(document.body));
  if (actual === recorded.value) {
    write(stdout, `${file}: the body matches its recorded hash (${actual})`);
    return EXIT_OK;
  }
  write(
    stderr,
    `docket: ${file} does not match its recorded hash\n` +
      `  recorded: ${recorded.value}\n` +
      `  actual:   ${actual}\n` +
      `  The body has changed since the freeze, or the file was assembled by hand.`,
  );
  return EXIT_ERROR;
}

/**
 * The only writes a frozen document takes, and the only writes this makes.
 *
 * Three keys, by name, and everything else refused: after the freeze the body
 * and the rest of the frontmatter are the record, and "fix the title while
 * you are in there" is exactly the edit this exists to not do. Every other
 * byte of the file is written back untouched.
 */
export function commandSet(file, key, value, options = {}) {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;

  if (!MUTABLE_KEYS.includes(key)) {
    write(
      stderr,
      `docket: set changes only ${MUTABLE_KEYS.join(", ")}; ` +
        `'${key}' is part of the frozen record and never changes. ` +
        `A wrong body or title means a correcting erratum, or a new document ` +
        `that supersedes this one.`,
    );
    return EXIT_USAGE;
  }
  if (value === undefined || value === "") {
    write(stderr, `docket: set ${key} needs a value`);
    return EXIT_USAGE;
  }

  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (error) {
    write(stderr, `docket: cannot read '${file}': ${error.message}`);
    return EXIT_ERROR;
  }
  const document = parseDocument(text);
  if (!document) {
    write(stderr, `docket: '${file}' has no frontmatter`);
    return EXIT_ERROR;
  }

  const lines = [...document.frontmatter];
  let said;

  if (key === "status") {
    if (!STATUSES.includes(value)) {
      write(
        stderr,
        `docket: '${value}' is not a status; the stages are ${STATUSES.join(", ")}`,
      );
      return EXIT_USAGE;
    }
    replaceKeyLine(lines, "status", `status: ${value}`);
    said = `Set status: ${value} on ${file}`;
  } else if (key === "superseded_by") {
    if (!/^\d+$/.test(value)) {
      write(
        stderr,
        `docket: superseded_by takes the successor's number, not '${value}'`,
      );
      return EXIT_USAGE;
    }
    replaceKeyLine(lines, "superseded_by", `superseded_by: ${value}`);
    said = `Set superseded_by: ${value} on ${file}`;
  } else {
    if (/[\r\n]/.test(value)) {
      write(stderr, "docket: an erratum is one line");
      return EXIT_USAGE;
    }
    const date = options.date ?? today();
    appendErratum(lines, `  - ${quote(`${date}: ${value}`)}`);
    said = `Appended a ${date} erratum to ${file}`;
  }

  fs.writeFileSync(file, `---\n${lines.join("\n")}\n---\n${document.body}`);
  write(stdout, said);
  return EXIT_OK;
}

function replaceKeyLine(lines, key, replacement) {
  const index = lines.findIndex((line) => line.startsWith(`${key}:`));
  if (index === -1) {
    lines.push(replacement);
  } else {
    lines[index] = replacement;
  }
}

function appendErratum(lines, item) {
  const index = lines.findIndex((line) => line.startsWith("errata:"));
  if (index === -1) {
    lines.push("errata:", item);
    return;
  }
  // `errata: []` becomes a block list on the first entry; after that, new
  // lines go after the last existing entry, so the list stays append-only.
  lines[index] = "errata:";
  let after = index + 1;
  while (after < lines.length && /^\s+-\s/.test(lines[after])) {
    after++;
  }
  lines.splice(after, 0, item);
}

// ---------------------------------------------------------------------------
// The CI check
// ---------------------------------------------------------------------------

function runGit(args, cwd) {
  const result = spawnSync("git", args, { cwd, encoding: "utf8" });
  return {
    status: result.status ?? EXIT_ERROR,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

/**
 * The immutability rule, read out of a git diff.
 *
 * For every changed `.md` file whose base version is a frozen docket document
 * - frontmatter saying `frozen` or `superseded`, with a recorded hash - the
 * change may touch `status`, `superseded_by` and `errata`, and nothing else:
 *
 * - the body must be byte-identical to the base;
 * - every other frontmatter key must be untouched;
 * - `errata` only grows - the base list must be a prefix of the new one;
 * - `status` may only move between `frozen` and `superseded`, because a
 *   status that thaws would put the same file outside this rule on the next
 *   pull request;
 * - the file itself must still exist.
 *
 * Everything else - new documents, drafts on a branch, files that are not
 * docket's - passes untouched. The check reads the base from git and the head
 * from the working tree, so it answers the same way in CI and at a prompt.
 */
export function ciCheck(baseRef, options = {}) {
  const cwd = options.dir ?? process.cwd();
  const violations = [];

  const diff = runGit(
    ["diff", "--name-status", "--no-renames", baseRef, "--"],
    cwd,
  );
  if (diff.status !== EXIT_OK) {
    return {
      error: `cannot diff against '${baseRef}': ${diff.stderr.trim()}`,
      violations,
      checked: 0,
    };
  }

  let checked = 0;
  for (const line of diff.stdout.split("\n")) {
    const changed = /^([A-Z])\t(.+)$/.exec(line);
    if (!changed || !changed[2].endsWith(".md")) {
      continue;
    }
    const [, change, file] = changed;

    const base = runGit(["show", `${baseRef}:${file}`], cwd);
    if (base.status !== EXIT_OK) {
      continue; // Not there at the base: a new document, which is always fine.
    }
    const before = parseDocument(base.stdout);
    if (!before) {
      continue;
    }
    const status = frontmatterEntry(before.frontmatter, "status")?.value;
    const hash = frontmatterEntry(before.frontmatter, "content_sha256")?.value;
    if (!FROZEN_STATUSES.includes(status) || !hash) {
      continue; // Not frozen at the base, or not a docket document at all.
    }

    checked++;
    if (change === "D" || !fs.existsSync(path.join(cwd, file))) {
      violations.push(`${file} is frozen and may not be deleted`);
      continue;
    }
    const after = parseDocument(fs.readFileSync(path.join(cwd, file), "utf8"));
    if (!after) {
      violations.push(`${file} is frozen and lost its frontmatter`);
      continue;
    }

    if (after.body !== before.body) {
      violations.push(
        `${file} is frozen; the body may not change. A correction is an ` +
          `erratum line, and substantive change is a new document that ` +
          `supersedes this one.`,
      );
    }
    compareFrontmatter(file, before, after, violations);
  }

  return { violations, checked };
}

function compareFrontmatter(file, before, after, violations) {
  const baseEntries = parseFrontmatter(before.frontmatter);
  const headEntries = parseFrontmatter(after.frontmatter);
  const base = new Map(baseEntries.map((entry) => [entry.key, entry]));
  const head = new Map(headEntries.map((entry) => [entry.key, entry]));

  for (const key of new Set([...base.keys(), ...head.keys()])) {
    if (!MUTABLE_KEYS.includes(key)) {
      const was = base.get(key);
      const is = head.get(key);
      if (
        !was ||
        !is ||
        was.value !== is.value ||
        was.items.join("\n") !== is.items.join("\n")
      ) {
        violations.push(
          `${file} is frozen; the frontmatter key '${key}' may not change - ` +
            `only ${MUTABLE_KEYS.join(", ")} stay writable`,
        );
      }
    }
  }

  const status = head.get("status")?.value;
  if (
    status !== base.get("status")?.value &&
    !FROZEN_STATUSES.includes(status)
  ) {
    violations.push(
      `${file} is frozen; status may move between ${FROZEN_STATUSES.join(" and ")}, ` +
        `never back to '${status}'`,
    );
  }

  const successor = head.get("superseded_by")?.value ?? "";
  if (successor !== "" && !/^\d+$/.test(successor)) {
    violations.push(
      `${file}: superseded_by must be the successor's number, not '${successor}'`,
    );
  }

  const errataBefore = base.get("errata")?.items ?? [];
  const errataAfter = head.get("errata")?.items ?? [];
  const prefix = errataBefore.every(
    (item, index) => errataAfter[index] === item,
  );
  if (!prefix || errataAfter.length < errataBefore.length) {
    violations.push(
      `${file}: errata is append-only; existing lines stay as they are`,
    );
  }
}

export function commandCiCheck(baseRef, options = {}) {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;

  const { error, violations, checked } = ciCheck(baseRef, options);
  if (error) {
    write(stderr, `docket: ${error}`);
    return EXIT_ERROR;
  }
  if (violations.length > 0) {
    write(
      stderr,
      `docket: the immutability check failed:\n` +
        violations.map((violation) => `- ${violation}`).join("\n"),
    );
    return EXIT_ERROR;
  }
  write(
    stdout,
    checked === 0
      ? "No frozen document was touched."
      : `${checked} frozen document(s) changed within the rule: only status, ` +
          `superseded_by and errata moved.`,
  );
  return EXIT_OK;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

const OPTION_CONFIG = {
  title: { type: "string" },
  created: { type: "string" },
  frozen: { type: "string" },
  backend: { type: "string" },
  body: { type: "string" },
  date: { type: "string" },
  dir: { type: "string" },
  help: { type: "boolean", short: "h" },
};

export function usage(invocation = "docket.mjs") {
  return `docket - the docket skill's helper: deterministic archive mechanics

Usage: node ${invocation} <command> [arguments] [options]

Commands:
  next <collection-dir>            The next free number, zero-padded - one past
                                   the highest numbered file; gaps stay gaps
  freeze <collection-dir> <n>      Assemble <nnnn>.md: frontmatter, the body,
                                   and the body's sha256
  verify <file>                    Recompute the hash against the frontmatter
  set <file> status <value>        Record a stage move
  set <file> superseded_by <n>     Point a frozen document at its successor
  set <file> errata <text>         Append one dated erratum line
  ci-check <base-ref>              Enforce immutability against a base revision

Options:
  --title <text>     freeze: the document's title
  --created <date>   freeze: when the draft was created (YYYY-MM-DD)
  --frozen <date>    freeze: the freeze date (default: today, UTC)
  --backend <ref>    freeze: where it was drafted - notion/page/<id>, a PR
                     URL, or 'git'
  --body <file>      freeze: the exported body ('-' reads stdin)
  --date <date>      set errata: the erratum's date (default: today, UTC)
  --dir <path>       ci-check: the archive repository (default: here)
  -h, --help         Show this

Everything is local files and local git; nothing here talks to a backend.
After the freeze only status, superseded_by and errata change - the body and
the rest of the frontmatter are the record.
`;
}

export function main(argv, options = {}) {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;
  const invocation = options.invocation ?? "docket.mjs";

  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      options: OPTION_CONFIG,
      allowPositionals: true,
      strict: true,
    });
  } catch (error) {
    write(stderr, `docket: ${error.message}`);
    return EXIT_USAGE;
  }

  const { values, positionals } = parsed;
  const command = positionals[0] ?? "help";

  if (values.help || command === "help") {
    write(stdout, usage(invocation));
    return EXIT_OK;
  }

  let shared;
  try {
    shared = {
      ...options,
      title: values.title,
      backend: values.backend,
      body: values.body,
      dir: values.dir ?? options.dir,
      created: readDate(values.created, "created"),
      frozen: readDate(values.frozen, "frozen"),
      date: readDate(values.date, "date"),
    };
  } catch (error) {
    write(stderr, `docket: ${error.message}`);
    return EXIT_USAGE;
  }

  switch (command) {
    case "next":
      if (!positionals[1]) {
        write(stderr, "docket: next needs a collection directory");
        return EXIT_USAGE;
      }
      return commandNext(positionals[1], shared);
    case "freeze":
      if (!positionals[1] || !positionals[2]) {
        write(
          stderr,
          "docket: freeze needs a collection directory and a number",
        );
        return EXIT_USAGE;
      }
      return commandFreeze(positionals[1], positionals[2], shared);
    case "verify":
      if (!positionals[1]) {
        write(stderr, "docket: verify needs a file");
        return EXIT_USAGE;
      }
      return commandVerify(positionals[1], shared);
    case "set":
      if (!positionals[1] || !positionals[2]) {
        write(stderr, "docket: set needs a file, a key and a value");
        return EXIT_USAGE;
      }
      return commandSet(positionals[1], positionals[2], positionals[3], shared);
    case "ci-check":
      if (!positionals[1]) {
        write(stderr, "docket: ci-check needs a base revision");
        return EXIT_USAGE;
      }
      return commandCiCheck(positionals[1], shared);
    default:
      write(
        stderr,
        `docket: unknown command '${command}'\n\n${usage(invocation)}`,
      );
      return EXIT_USAGE;
  }
}

// Run directly, rather than imported by a test.
if (
  process.argv[1] &&
  import.meta.url.endsWith(path.basename(process.argv[1]))
) {
  process.exitCode = main(process.argv.slice(2), {
    invocation: process.argv[1],
  });
}
