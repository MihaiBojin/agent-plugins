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

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { main } from "../plugins/docket/skills/docket/docket.mjs";

/**
 * The docket helper is the deterministic half of a promise: numbers are never
 * reused, a frozen body never changes, and the recorded hash stays checkable
 * forever. Every test here is about a way that promise could quietly break -
 * two writers allocating the same number, a "small fix" landing in a frozen
 * body, a hash that no longer names the text it was recorded against.
 */

/** sha256 of "hello world\n", the classic. */
const HELLO_SHA =
  "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447";

function temporary() {
  return fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "docket-")));
}

function collection(root, name = "rfc", backend = "git") {
  const directory = path.join(root, name);
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(
    path.join(directory, "docket.toml"),
    `profile = "rfc"\nbackend = "${backend}"\nwidth = 4\n`,
  );
  return directory;
}

/** Runs the helper's CLI in-process, capturing what it said. */
function run(argv, options = {}) {
  let stdout = "";
  let stderr = "";
  const status = main(argv, {
    ...options,
    stdout: { write: (text) => (stdout += text) },
    stderr: { write: (text) => (stderr += text) },
  });
  return { status, stdout, stderr };
}

function git(cwd, args) {
  const result = spawnSync(
    "git",
    ["-c", "user.email=docket@test", "-c", "user.name=docket", ...args],
    { cwd, encoding: "utf8" },
  );
  expect(result.status).toBe(0);
  return result.stdout.trim();
}

/** A collection inside a git repo, with one frozen document committed. */
function frozenArchive() {
  const root = temporary();
  git(root, ["init", "--quiet"]);
  const directory = collection(root, "rfc");
  fs.writeFileSync(path.join(root, "body.md"), "hello world\n");

  const froze = run([
    "freeze",
    directory,
    "1",
    "--title",
    "The first document",
    "--created",
    "2026-08-12",
    "--frozen",
    "2026-08-20",
    "--backend",
    "git",
    "--body",
    path.join(root, "body.md"),
  ]);
  expect(froze.status).toBe(0);
  fs.rmSync(path.join(root, "body.md"));

  git(root, ["add", "."]);
  git(root, ["commit", "--quiet", "-m", "freeze rfc 0001"]);
  return {
    root,
    file: path.join(directory, "0001.md"),
    base: git(root, ["rev-parse", "HEAD"]),
  };
}

describe("next", () => {
  test("is one past the highest number, and gaps stay gaps", () => {
    const directory = collection(temporary());
    for (const name of ["0001.md", "0002.md", "0004.md"]) {
      fs.writeFileSync(path.join(directory, name), "x\n");
    }

    const { status, stdout } = run(["next", directory]);
    expect(status).toBe(0);
    // 0003 is a burned number - a withdrawn document, never refilled.
    expect(stdout).toBe("0005\n");
  });

  test("starts an empty collection at one, zero-padded to the width", () => {
    const { status, stdout } = run(["next", collection(temporary())]);
    expect(status).toBe(0);
    expect(stdout).toBe("0001\n");
  });

  test("refuses a directory that is not a collection", () => {
    const { status, stderr } = run(["next", temporary()]);
    expect(status).toBe(1);
    expect(stderr).toContain("docket.toml");
  });
});

describe("freeze and verify", () => {
  test("round-trips: the recorded hash is the body's, and verify agrees", () => {
    const root = temporary();
    const directory = collection(root);
    fs.writeFileSync(path.join(root, "body.md"), "hello world\n");

    const froze = run([
      "freeze",
      directory,
      "12",
      "--title",
      'A title with "quotes"',
      "--created",
      "2026-08-01",
      "--frozen",
      "2026-08-20",
      "--backend",
      "notion/page/aab35f24c80846f5a0d3311a9d78f21f",
      "--body",
      path.join(root, "body.md"),
    ]);
    expect(froze.status).toBe(0);

    const file = path.join(directory, "0012.md");
    const written = fs.readFileSync(file, "utf8");
    expect(written).toContain(`content_sha256: ${HELLO_SHA}`);
    expect(written).toContain("status: frozen");
    expect(written.endsWith("---\n\nhello world\n")).toBe(true);

    expect(run(["verify", file]).status).toBe(0);

    // A changed body is exactly what verify exists to catch.
    fs.writeFileSync(file, written.replace("hello world", "hello there"));
    const changed = run(["verify", file]);
    expect(changed.status).toBe(1);
    expect(changed.stderr).toContain("does not match");
  });

  test("never overwrites an existing number", () => {
    const root = temporary();
    const directory = collection(root);
    fs.writeFileSync(path.join(directory, "0007.md"), "taken\n");
    fs.writeFileSync(path.join(root, "body.md"), "hello world\n");

    const { status, stderr } = run([
      "freeze",
      directory,
      "7",
      "--title",
      "A collision",
      "--created",
      "2026-08-01",
      "--backend",
      "git",
      "--body",
      path.join(root, "body.md"),
    ]);
    expect(status).toBe(1);
    expect(stderr).toContain("never reused");
    expect(fs.readFileSync(path.join(directory, "0007.md"), "utf8")).toBe(
      "taken\n",
    );
  });
});

describe("set", () => {
  test("refuses every key that is not status, superseded_by or errata", () => {
    const { file } = frozenArchive();
    const before = fs.readFileSync(file, "utf8");

    for (const [key, value] of [
      ["title", "A better title"],
      ["content_sha256", "0".repeat(64)],
      ["number", "2"],
      ["created", "2026-01-01"],
    ]) {
      const { status, stderr } = run(["set", file, key, value]);
      expect(status).toBe(2);
      expect(stderr).toContain(key);
    }
    // Refused means untouched, byte for byte.
    expect(fs.readFileSync(file, "utf8")).toBe(before);
  });

  test("writes the three keys it allows, and only their lines", () => {
    const { file } = frozenArchive();

    expect(run(["set", file, "superseded_by", "2"]).status).toBe(0);
    expect(run(["set", file, "status", "superseded"]).status).toBe(0);
    expect(
      run([
        "set",
        file,
        "errata",
        "section 2 misnames the table",
        "--date",
        "2026-08-21",
      ]).status,
    ).toBe(0);

    const text = fs.readFileSync(file, "utf8");
    expect(text).toContain("superseded_by: 2");
    expect(text).toContain("status: superseded");
    expect(text).toContain('- "2026-08-21: section 2 misnames the table"');
    // The body and its hash are untouched by all three.
    expect(text.endsWith("---\n\nhello world\n")).toBe(true);
    expect(run(["verify", file]).status).toBe(0);
  });

  test("refuses a status outside the stage set", () => {
    const { file } = frozenArchive();
    const { status, stderr } = run(["set", file, "status", "finished"]);
    expect(status).toBe(2);
    expect(stderr).toContain("not a status");
  });
});

describe("ci-check", () => {
  test("accepts a supersession: superseded_by, status and an erratum", () => {
    const { root, file, base } = frozenArchive();
    run(["set", file, "superseded_by", "2"]);
    run(["set", file, "status", "superseded"]);
    run(["set", file, "errata", "superseded in full", "--date", "2026-08-22"]);

    const { status, stdout } = run(["ci-check", base], { dir: root });
    expect(status).toBe(0);
    expect(stdout).toContain("within the rule");
  });

  test("rejects a body edit to a frozen file", () => {
    const { root, file, base } = frozenArchive();
    fs.writeFileSync(
      file,
      fs
        .readFileSync(file, "utf8")
        .replace("hello world", "hello world, but improved"),
    );

    const { status, stderr } = run(["ci-check", base], { dir: root });
    expect(status).toBe(1);
    expect(stderr).toContain("the body may not change");
  });

  test("rejects an immutable frontmatter edit and a thawing status", () => {
    const { root, file, base } = frozenArchive();
    fs.writeFileSync(
      file,
      fs
        .readFileSync(file, "utf8")
        .replace('title: "The first document"', 'title: "A quiet rename"')
        .replace("status: frozen", "status: draft"),
    );

    const { status, stderr } = run(["ci-check", base], { dir: root });
    expect(status).toBe(1);
    expect(stderr).toContain("'title' may not change");
    expect(stderr).toContain("never back to 'draft'");
  });

  test("leaves new documents and untouched files alone", () => {
    const { root, base } = frozenArchive();
    fs.writeFileSync(path.join(root, "rfc", "0002.md"), "a new draft\n");
    git(root, ["add", "rfc/0002.md"]);

    const { status, stdout } = run(["ci-check", base], { dir: root });
    expect(status).toBe(0);
    expect(stdout).toContain("No frozen document was touched");
  });
});
