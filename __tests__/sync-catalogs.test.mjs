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
import path from "node:path";
import { syncCatalogs } from "../scripts/sync-catalogs.mjs";
import { marketplace, plugin, readJson, writeJson } from "./fixtures.mjs";

/**
 * The catalogs are the only generated files. What matters is that both
 * describe the same inventory, that each entry is derived rather than typed,
 * and that a plugin arriving does not disturb one that was already there.
 */

const CLAUDE = ".claude-plugin/marketplace.json";
const CODEX = ".agents/plugins/marketplace.json";
const names = (root, catalog) =>
  readJson(root, catalog).plugins.map((entry) => entry.name);

describe("syncCatalogs", () => {
  const roots = [];
  const build = (...plugins) => {
    const root = marketplace();
    roots.push(root);
    for (const [name, overrides] of plugins) {
      plugin(root, name, overrides);
    }
    return root;
  };

  afterEach(() => {
    for (const root of roots.splice(0)) {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });

  it("writes both catalogs from the plugins that are there", () => {
    const root = build(["docket", { version: "0.1.0" }]);

    const { errors, changed } = syncCatalogs({ root });

    expect(errors).toEqual([]);
    expect(changed).toEqual([CLAUDE, CODEX]);

    const claude = readJson(root, CLAUDE).plugins[0];
    expect(claude.source).toBe("./plugins/docket");
    expect(claude.version).toBe("0.1.0");
    expect(claude.license).toBe("Apache-2.0");

    const codex = readJson(root, CODEX).plugins[0];
    expect(codex.source).toEqual({ source: "local", path: "./plugins/docket" });
    expect(codex.policy).toEqual({
      installation: "AVAILABLE",
      authentication: "ON_INSTALL",
    });
    expect(codex.category).toBe("Developer Tools");
    expect("version" in codex).toBe(false);
  });

  it("says nothing needs doing when the catalogs already agree", () => {
    const root = build(["docket", { version: "0.1.0" }]);
    syncCatalogs({ root });

    expect(syncCatalogs({ root }).changed).toEqual([]);
  });

  it("reports what would change without writing it, under --check", () => {
    const root = build(["docket", {}]);
    const before = fs.readFileSync(path.join(root, CLAUDE), "utf8");

    expect(syncCatalogs({ root, check: true }).changed).toEqual([
      CLAUDE,
      CODEX,
    ]);
    expect(fs.readFileSync(path.join(root, CLAUDE), "utf8")).toBe(before);
  });

  it("appends a new plugin and leaves the first where it was", () => {
    const root = build(["docket", { version: "0.1.0" }]);
    syncCatalogs({ root });
    const first = readJson(root, CLAUDE).plugins[0];

    plugin(root, "scaffold", { version: "2.3.4" });
    syncCatalogs({ root });

    expect(names(root, CLAUDE)).toEqual(["docket", "scaffold"]);
    expect(names(root, CODEX)).toEqual(["docket", "scaffold"]);
    expect(readJson(root, CLAUDE).plugins[0]).toEqual(first);
  });

  it("keeps a plugin's position when its version moves", () => {
    const root = build(["docket", { version: "0.1.0" }], ["scaffold", {}]);
    syncCatalogs({ root });
    const scaffold = readJson(root, CLAUDE).plugins[1];

    plugin(root, "docket", { version: "0.2.0" });
    syncCatalogs({ root });

    expect(names(root, CLAUDE)).toEqual(["docket", "scaffold"]);
    expect(readJson(root, CLAUDE).plugins[0].version).toBe("0.2.0");
    expect(readJson(root, CLAUDE).plugins[1]).toEqual(scaffold);
  });

  it("drops an entry whose plugin was removed", () => {
    const root = build(["docket", {}], ["scaffold", {}]);
    syncCatalogs({ root });

    fs.rmSync(path.join(root, "plugins", "scaffold"), { recursive: true });
    syncCatalogs({ root });

    expect(names(root, CLAUDE)).toEqual(["docket"]);
    expect(names(root, CODEX)).toEqual(["docket"]);
  });

  it("rewrites an entry somebody edited by hand", () => {
    const root = build(["docket", {}]);
    syncCatalogs({ root });

    const catalog = readJson(root, CLAUDE);
    catalog.plugins[0].description = "written straight into the catalog";
    writeJson(root, CLAUDE, catalog);

    syncCatalogs({ root });

    expect(readJson(root, CLAUDE).plugins[0].description).toBe(
      "The docket plugin",
    );
  });

  /**
   * A catalog is what a client reads before fetching anything. Listing
   * something broken is worse than listing nothing: the install succeeds and
   * the plugin does not work.
   */
  it("writes no entry for a plugin that does not validate", () => {
    const root = build(["docket", { codex: { skills: "./elsewhere/" } }]);

    const { errors, changed } = syncCatalogs({ root });

    expect(errors.length).toBeGreaterThan(0);
    expect(errors[0]).toContain("docket:");
    expect(changed).toEqual([]);
    expect(names(root, CLAUDE)).toEqual([]);
  });

  it("refuses a checkout that is not this marketplace", () => {
    const root = marketplace({ name: "someone-else" });
    roots.push(root);
    plugin(root, "docket", {});

    expect(syncCatalogs({ root }).errors[0]).toContain("not 'mihaibojin'");
  });

  it("writes the JSON a formatter would leave alone", () => {
    const root = build(["docket", {}]);
    syncCatalogs({ root });

    for (const catalog of [CLAUDE, CODEX]) {
      const text = fs.readFileSync(path.join(root, catalog), "utf8");
      expect(text).toBe(`${JSON.stringify(JSON.parse(text), null, 2)}\n`);
    }
  });
});
