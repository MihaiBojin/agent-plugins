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
import { checkVersionBump } from "../scripts/check-version-bump.mjs";
import { marketplace, plugin } from "./fixtures.mjs";

/**
 * A plugin that changed has to say so in its version, and the diff against the
 * base branch is the only place the rule can be enforced. Without it a client
 * that already has 0.1.0 compares versions, finds the same number, and never
 * fetches the fix - quietly, on every machine that already had it.
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

describe("checkVersionBump", () => {
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
    const result = checkVersionBump({
      root,
      base: "origin/main",
      git: fakeGit({ changed: [], versions: { docket: "0.1.0" } }),
    });

    expect(result).toEqual({ errors: [], bumped: [] });
  });

  it("passes when a changed plugin was bumped", () => {
    const root = build(["docket", "0.2.0"]);
    const result = checkVersionBump({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.1.0" } }),
    });

    expect(result.errors).toEqual([]);
    expect(result.bumped).toEqual(["docket 0.1.0 -> 0.2.0"]);
  });

  it("catches a changed plugin whose version stood still", () => {
    const root = build(["docket", "0.1.0"]);
    const result = checkVersionBump({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.1.0" } }),
    });

    expect(result.errors).toHaveLength(1);
    expect(result.errors[0]).toContain("still 0.1.0");
  });

  it("catches a version that went backwards", () => {
    const root = build(["docket", "0.1.0"]);
    const result = checkVersionBump({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["docket"], versions: { docket: "0.2.0" } }),
    });

    expect(result.errors).toHaveLength(1);
    expect(result.errors[0]).toContain("still 0.1.0");
  });

  it("asks nothing of a plugin that is new", () => {
    const root = build(["scaffold", "0.1.0"]);
    const result = checkVersionBump({
      root,
      base: "origin/main",
      git: fakeGit({ changed: ["scaffold"], versions: {} }),
    });

    expect(result.errors).toEqual([]);
    expect(result.bumped).toEqual(["scaffold is new"]);
  });

  it("leaves the other plugins alone", () => {
    const root = build(["docket", "0.1.0"], ["scaffold", "2.3.4"]);
    const result = checkVersionBump({
      root,
      base: "origin/main",
      git: fakeGit({
        changed: ["scaffold"],
        versions: { docket: "0.1.0", scaffold: "2.3.3" },
      }),
    });

    expect(result.errors).toEqual([]);
    expect(result.bumped).toEqual(["scaffold 2.3.3 -> 2.3.4"]);
  });

  it("says so when the base ref is not there to compare against", () => {
    const root = build(["docket", "0.1.0"]);
    const result = checkVersionBump({
      root,
      base: "origin/main",
      git: () => ({ status: 128, stdout: "", stderr: "bad revision\n" }),
    });

    expect(result.errors[0]).toContain("cannot compare against origin/main");
  });
});
