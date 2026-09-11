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
import { checkRelease } from "../scripts/check-release.mjs";
import { marketplace, plugin } from "./fixtures.mjs";

/**
 * A plugin that changed declares the release: a new version, and a changelog
 * section carrying it. The diff against the base branch is the only place
 * either rule can be enforced. Without the first, a client that already has
 * 0.1.0 compares versions, finds the same number, and never fetches the fix.
 * Without the second, the reasoning is gone by the time somebody needs it.
 *
 * `git` is injected so these describe situations rather than build repositories.
 */
function fakeGit({ changed = [], versions = {} }) {
  return (_cwd, args) => {
    const ok = (stdout) => ({ status: 0, stdout, stderr: "" });
    if (args[0] === "diff") {
      const name = args.at(-1).split("/").at(-1);
      return ok(changed.includes(name) ? `plugins/${name}/README.md\n` : "");
    }
    if (args[0] === "show") {
      const name = args[1].split(":")[1].split("/")[1];
      if (!Object.hasOwn(versions, name)) {
        return { status: 128, stdout: "", stderr: "path does not exist" };
      }
      return ok(JSON.stringify({ name, version: versions[name] }));
    }
    return { status: 1, stdout: "", stderr: `unexpected: ${args.join(" ")}` };
  };
}

describe("checkRelease", () => {
  const roots = [];
  const build = (...plugins) => {
    const root = marketplace();
    roots.push(root);
    for (const [name, version] of plugins) {
      plugin(root, name, { version });
    }
    return root;
  };

  afterEach(() => {
    for (const root of roots.splice(0)) {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });

  it("passes when nothing changed", () => {
    const root = build(["docket", "0.1.0"]);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: [], versions: { docket: "0.1.0" } }),
    });

    expect(result).toEqual({ errors: [], released: [] });
  });

  it("passes when a changed plugin was bumped", () => {
    const root = build(["docket", "0.2.0"]);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.1.0" } }),
    });

    expect(result.errors).toEqual([]);
    expect(result.released).toEqual(["docket 0.1.0 -> 0.2.0"]);
  });

  it("catches a changed plugin whose version stood still", () => {
    const root = build(["docket", "0.1.0"]);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.1.0" } }),
    });

    expect(result.errors).toHaveLength(1);
    expect(result.errors[0]).toContain("still 0.1.0");
  });

  it("catches a version that went backwards", () => {
    const root = build(["docket", "0.1.0"]);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.2.0" } }),
    });

    expect(result.errors).toHaveLength(1);
    expect(result.errors[0]).toContain("still 0.1.0");
  });

  it("asks nothing of a plugin that is new", () => {
    const root = build(["scaffold", "0.1.0"]);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["scaffold"], versions: {} }),
    });

    expect(result.errors).toEqual([]);
    expect(result.released).toEqual(["scaffold is new, at 0.1.0"]);
  });

  it("leaves the other plugins alone", () => {
    const root = build(["docket", "0.1.0"], ["scaffold", "2.3.4"]);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({
        changed: ["scaffold"],
        versions: { docket: "0.1.0", scaffold: "2.3.3" },
      }),
    });

    expect(result.errors).toEqual([]);
    expect(result.released).toEqual(["scaffold 2.3.3 -> 2.3.4"]);
  });

  it("catches a bumped plugin whose changelog never mentions the version", () => {
    const root = build(["docket", "0.2.0"]);
    fs.writeFileSync(
      `${root}/plugins/docket/CHANGELOG.md`,
      "# docket\n\n## 0.1.0\n\nThe first release.\n",
    );
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.1.0" } }),
    });

    expect(result.released).toEqual(["docket 0.1.0 -> 0.2.0"]);
    expect(result.errors).toHaveLength(1);
    expect(result.errors[0]).toContain("no section for 0.2.0");
  });

  it("catches a plugin with no changelog at all", () => {
    const root = build(["docket", "0.2.0"]);
    fs.rmSync(`${root}/plugins/docket/CHANGELOG.md`);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.1.0" } }),
    });

    expect(result.errors).toHaveLength(1);
    expect(result.errors[0]).toContain("has no CHANGELOG.md");
  });

  it("asks for a changelog entry from a new plugin too", () => {
    const root = build(["scaffold", "0.1.0"]);
    fs.rmSync(`${root}/plugins/scaffold/CHANGELOG.md`);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["scaffold"], versions: {} }),
    });

    expect(result.released).toEqual(["scaffold is new, at 0.1.0"]);
    expect(result.errors).toHaveLength(1);
  });

  it("takes a dated heading, the way release-notes writes one", () => {
    const root = build(["docket", "0.2.0"]);
    fs.writeFileSync(
      `${root}/plugins/docket/CHANGELOG.md`,
      "# docket\n\n## 0.2.0 - 2026-09-11\n\nWhat changed.\n",
    );
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.1.0" } }),
    });

    expect(result.errors).toEqual([]);
  });

  it("does not read 0.2.0 out of 0.2.0-rc1", () => {
    const root = build(["docket", "0.2.0"]);
    fs.writeFileSync(
      `${root}/plugins/docket/CHANGELOG.md`,
      "# docket\n\n## 0.2.0-rc1\n\nNot the release.\n",
    );
    const result = checkRelease({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.1.0" } }),
    });

    expect(result.errors).toHaveLength(1);
  });

  it("says so when the base ref is not there to compare against", () => {
    const root = build(["docket", "0.1.0"]);
    const result = checkRelease({
      root,
      base: "origin/main",
      git: () => ({ status: 128, stdout: "", stderr: "bad revision\n" }),
    });

    expect(result.errors[0]).toContain("cannot compare against origin/main");
  });
});
