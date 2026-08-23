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

/**
 * What both catalogs and both publishers agree on.
 *
 * Two clients read this repository through files of their own, and neither can
 * see the other. Everything they have to share - the marketplace name, where a
 * plugin's files live, how the JSON is written - is here, so the publisher and
 * the validator cannot drift into disagreeing about it.
 */

/** The name a user types after `@` when installing. Both catalogs carry it. */
export const MARKETPLACE_NAME = "MihaiBojin";

/** Claude Code's catalog. */
export const CLAUDE_CATALOG = ".claude-plugin/marketplace.json";

/** Codex's catalog. */
export const CODEX_CATALOG = ".agents/plugins/marketplace.json";

/** Where a published plugin's files live, relative to the repository root. */
export const PLUGINS_DIR = "plugins";

export const CLAUDE_MANIFEST = ".claude-plugin/plugin.json";
export const CODEX_MANIFEST = ".codex-plugin/plugin.json";

/** Strict X.Y.Z. No prereleases: a marketplace has nowhere to show one. */
export const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

/**
 * A plugin name that is also safe as a single path segment.
 *
 * The name decides which directory is deleted and rewritten, so it is checked
 * against a pattern rather than merely rejected for containing a separator.
 */
export const PLUGIN_NAME = /^[a-z0-9][a-z0-9-]*$/;

/** Every published plugin's source path, in the form each client expects. */
export const claudeSource = (name) => `./${PLUGINS_DIR}/${name}`;
export const codexSource = (name) => ({
  source: "local",
  path: `./${PLUGINS_DIR}/${name}`,
});

/**
 * Claude Code's entry: the source, and the descriptive metadata it shows.
 *
 * The version is written here even though the plugin's own manifest carries
 * it, because the catalog is what a client reads before fetching anything. It
 * is generated from that manifest, so the two cannot drift.
 */
export function claudeEntry(manifest) {
  return withoutUndefined({
    name: manifest.name,
    source: claudeSource(manifest.name),
    description: manifest.description,
    version: manifest.version,
    author: manifest.author,
    homepage: manifest.homepage,
    repository: manifest.repository,
    license: manifest.license,
    keywords: manifest.keywords,
  });
}

/**
 * Codex's entry, in Codex's schema.
 *
 * The descriptive metadata Claude Code keeps in the catalog lives in Codex's
 * own manifest under `interface`, so the entry carries only what Codex asks a
 * catalog for: where the plugin is, whether it may be installed, and when it
 * authenticates. `AVAILABLE` and `ON_INSTALL` are Codex's defaults for a new
 * entry, stated rather than left implicit.
 */
export function codexEntry(manifest) {
  return {
    name: manifest.name,
    source: codexSource(manifest.name),
    policy: { installation: "AVAILABLE", authentication: "ON_INSTALL" },
    category: manifest.interface.category,
  };
}

function withoutUndefined(entry) {
  return Object.fromEntries(
    Object.entries(entry).filter(([, value]) => value !== undefined),
  );
}

export function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

/**
 * The one way this repository writes JSON.
 *
 * A generated file that a formatter would rewrite is a file that shows up as
 * dirty in the next unrelated pull request, and then gets committed by hand -
 * which is how a generated catalog stops being generated. The validator
 * re-serialises both catalogs and compares the bytes, so this is enforced
 * rather than merely intended.
 */
export function serializeJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, serializeJson(value));
}

/** Compares strict semver, returning the usual -1 / 0 / 1. */
export function compareVersions(left, right) {
  const a = left.split(".").map(Number);
  const b = right.split(".").map(Number);
  for (let index = 0; index < 3; index++) {
    if (a[index] !== b[index]) {
      return a[index] < b[index] ? -1 : 1;
    }
  }
  return 0;
}
