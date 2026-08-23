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
import { validateMarketplaces } from "../scripts/validate-marketplaces.mjs";
import {
  marketplace,
  plugin,
  readJson,
  write,
  writeJson,
} from "./fixtures.mjs";

/**
 * Neither client validates the other's catalog, and this repository is only
 * useful when both say the same thing. Every case below is a marketplace one of
 * the two vendors would accept on its own.
 */

const CLAUDE = ".claude-plugin/marketplace.json";
const CODEX = ".agents/plugins/marketplace.json";

describe("validateMarketplaces", () => {
  const roots = [];

  /** Two plugins, which is the smallest interesting marketplace. */
  const published = () => {
    const root = marketplace();
    roots.push(root);
    plugin(root, "docket", { version: "0.1.0" });
    plugin(root, "scaffold", { version: "2.3.4" });
    syncCatalogs({ root });
    return root;
  };
  const failure = (root) => validateMarketplaces({ root }).errors.join("\n");

  afterEach(() => {
    for (const root of roots.splice(0)) {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });

  it("passes on what the sync wrote", () => {
    const root = published();
    expect(validateMarketplaces({ root })).toEqual({
      plugins: ["docket", "scaffold"],
      errors: [],
    });
  });

  it("passes on an empty marketplace", () => {
    const root = marketplace();
    roots.push(root);
    expect(validateMarketplaces({ root })).toEqual({ plugins: [], errors: [] });
  });

  it("tolerates the placeholder that keeps plugins/ in git", () => {
    const root = marketplace();
    roots.push(root);
    write(root, "plugins/.gitkeep", "");

    expect(validateMarketplaces({ root })).toEqual({ plugins: [], errors: [] });
  });

  it("catches catalogs that list different plugins", () => {
    const root = published();
    const codex = readJson(root, CODEX);
    codex.plugins.pop();
    writeJson(root, CODEX, codex);

    expect(failure(root)).toMatch(/list different plugins/);
  });

  it("catches catalogs that list the same plugins in a different order", () => {
    const root = published();
    const codex = readJson(root, CODEX);
    codex.plugins.reverse();
    writeJson(root, CODEX, codex);

    expect(failure(root)).toMatch(/list different plugins/);
  });

  it("catches a catalog version that is not the plugin's version", () => {
    const root = published();
    const claude = readJson(root, CLAUDE);
    claude.plugins[0].version = "9.9.9";
    writeJson(root, CLAUDE, claude);

    expect(failure(root)).toMatch(
      /lists docket 9\.9\.9, but the plugin is 0\.1\.0/,
    );
  });

  it("catches manifests inside one plugin that disagree", () => {
    const root = published();
    const manifest = readJson(root, "plugins/docket/.codex-plugin/plugin.json");
    manifest.version = "0.9.0";
    writeJson(root, "plugins/docket/.codex-plugin/plugin.json", manifest);

    expect(failure(root)).toMatch(/carries two versions/);
  });

  it("catches a source pointing outside plugins/", () => {
    const root = published();
    const claude = readJson(root, CLAUDE);
    claude.plugins[0].source = "./plugins/../../elsewhere";
    writeJson(root, CLAUDE, claude);

    expect(failure(root)).toMatch(/points outside plugins\//);
  });

  it("catches a duplicated plugin name", () => {
    const root = published();
    const claude = readJson(root, CLAUDE);
    claude.plugins.push({ ...claude.plugins[0] });
    writeJson(root, CLAUDE, claude);

    expect(failure(root)).toMatch(/lists 'docket' twice/);
  });

  it("catches a catalog entry with no plugin behind it", () => {
    const root = published();
    fs.rmSync(path.join(root, "plugins/docket"), { recursive: true });

    expect(failure(root)).toMatch(/in both catalogs but not in the repository/);
  });

  it("catches a plugin directory that is in neither catalog", () => {
    const root = published();
    plugin(root, "stowaway", {});

    expect(failure(root)).toMatch(
      /plugins\/stowaway\/ is in the repository but in neither catalog/,
    );
  });

  it("catches a symlink in a published plugin", () => {
    const root = published();
    fs.symlinkSync(
      "/etc/passwd",
      path.join(root, "plugins/docket/skills/leak.md"),
    );

    expect(failure(root)).toMatch(/no symlinks/);
  });

  it("catches files that have no business being published", () => {
    const root = published();
    write(
      root,
      "plugins/docket/.env",
      "DATABASE_URL=postgres://localhost/db\n",
    );
    write(root, "plugins/scaffold/deploy.pem", "irrelevant\n");

    const errors = failure(root);
    expect(errors).toMatch(/plugins\/docket\/\.env does not belong/);
    expect(errors).toMatch(/plugins\/scaffold\/deploy\.pem does not belong/);
  });

  it("catches a secret that arrived inside an ordinary file", () => {
    const root = published();
    write(
      root,
      "plugins/docket/skills/docket/reference.md",
      "Try `DATABASE_URL=postgres://docket:hunter2@db.example.com/documents`\n",
    );
    write(
      root,
      "plugins/scaffold/README.md",
      "-----BEGIN OPENSSH PRIVATE KEY-----\n",
    );

    const errors = failure(root);
    expect(errors).toMatch(/connection string with a password/);
    expect(errors).toMatch(/a private key/);
  });

  it("does not mistake a documented placeholder for a secret", () => {
    const root = published();
    write(
      root,
      "plugins/docket/README.md",
      'DATABASE_URL="postgres://..." docket freeze rfc-0017\n',
    );

    expect(validateMarketplaces({ root }).errors).toEqual([]);
  });

  it("catches a catalog somebody reformatted by hand", () => {
    const root = published();
    fs.writeFileSync(
      path.join(root, CODEX),
      JSON.stringify(readJson(root, CODEX)),
    );

    expect(failure(root)).toMatch(/not in the form the publisher writes/);
  });

  it("catches a marketplace renamed out from under its users", () => {
    const root = published();
    const claude = readJson(root, CLAUDE);
    claude.name = "MihaiBojin-plugins";
    writeJson(root, CLAUDE, claude);

    expect(failure(root)).toMatch(/names the marketplace 'MihaiBojin-plugins'/);
  });

  it("catches a Codex entry with no installation policy", () => {
    const root = published();
    const codex = readJson(root, CODEX);
    delete codex.plugins[0].policy;
    writeJson(root, CODEX, codex);

    expect(failure(root)).toMatch(/no installation and authentication policy/);
  });

  it("catches metadata that only the catalog knows about", () => {
    const root = published();
    const claude = readJson(root, CLAUDE);
    claude.plugins[0].description = "written straight into the catalog";
    writeJson(root, CLAUDE, claude);

    expect(failure(root)).toMatch(/is not what the publisher generates/);
  });
});
