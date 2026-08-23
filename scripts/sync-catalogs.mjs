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
import { parseArgs } from "node:util";
import {
  CLAUDE_CATALOG,
  CLAUDE_MANIFEST,
  CODEX_CATALOG,
  CODEX_MANIFEST,
  MARKETPLACE_NAME,
  PLUGINS_DIR,
  claudeEntry,
  codexEntry,
  readJson,
  serializeJson,
} from "./catalogs.mjs";
import { REPOSITORY_ROOT, validatePlugin } from "./validate-plugin.mjs";

/**
 * Rewrites both catalogs from the plugins in `plugins/`.
 *
 *     npm run sync              write them
 *     npm run sync -- --check   say whether they are already right
 *
 * The catalogs are the only generated files here. Each entry is derived from
 * that plugin's own manifests, in that client's schema, so the two clients
 * cannot end up describing different things - which is the failure neither
 * vendor's validator can see, since each reads only its own file.
 *
 * A plugin that does not validate gets no entry written at all. A catalog is
 * what a client reads before fetching anything, and listing something broken is
 * worse than listing nothing: the install succeeds and the plugin does not work.
 */
export function syncCatalogs({ root = REPOSITORY_ROOT, check = false } = {}) {
  const marketplace = path.resolve(root);
  const directory = path.join(marketplace, PLUGINS_DIR);

  const plugins = fs.existsSync(directory)
    ? fs
        .readdirSync(directory, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name)
        .sort()
    : [];

  const errors = [];
  const entries = {};
  for (const name of plugins) {
    const at = path.join(directory, name);
    const failures = validatePlugin({ root: at, name }).errors;
    if (failures.length > 0) {
      errors.push(...failures.map((failure) => `${name}: ${failure}`));
      continue;
    }
    entries[name] = {
      claude: claudeEntry(readJson(path.join(at, CLAUDE_MANIFEST))),
      codex: codexEntry(readJson(path.join(at, CODEX_MANIFEST))),
    };
  }
  if (errors.length > 0) {
    return { errors, changed: [], plugins };
  }

  const changed = [];
  for (const [client, relative] of [
    ["claude", CLAUDE_CATALOG],
    ["codex", CODEX_CATALOG],
  ]) {
    const file = path.join(marketplace, relative);
    const catalog = readJson(file);
    if (catalog.name !== MARKETPLACE_NAME) {
      return {
        errors: [
          `${relative} is the '${catalog.name}' marketplace, not '${MARKETPLACE_NAME}'`,
        ],
        changed: [],
        plugins,
      };
    }

    // Order is what Codex renders by, so a plugin that is already listed keeps
    // its place and a new one goes on the end.
    const listed = catalog.plugins
      .map((entry) => entry?.name)
      .filter((name) => Object.hasOwn(entries, name));
    const appended = plugins.filter((name) => !listed.includes(name));
    catalog.plugins = [...listed, ...appended].map(
      (name) => entries[name][client],
    );

    const wanted = serializeJson(catalog);
    if (fs.readFileSync(file, "utf8") !== wanted) {
      changed.push(relative);
      if (!check) {
        fs.writeFileSync(file, wanted);
      }
    }
  }

  return { errors: [], changed, plugins };
}

// Run directly, rather than imported by a test.
if (
  process.argv[1] &&
  import.meta.url.endsWith(path.basename(process.argv[1]))
) {
  const { values } = parseArgs({
    options: { root: { type: "string" }, check: { type: "boolean" } },
  });

  const { errors, changed, plugins } = syncCatalogs(values);
  if (errors.length > 0) {
    process.stderr.write("Refusing to write a catalog for a broken plugin:\n");
    for (const error of errors) {
      process.stderr.write(`- ${error}\n`);
    }
    process.exit(1);
  }

  if (changed.length === 0) {
    process.stdout.write(
      `Both catalogs already describe ${plugins.join(", ") || "no plugins"}\n`,
    );
    process.exit(0);
  }
  if (values.check) {
    process.stderr.write(
      `${changed.join(" and ")} ${changed.length === 1 ? "is" : "are"} out of step with plugins/. Run \`npm run sync\`.\n`,
    );
    process.exit(1);
  }
  process.stdout.write(`Wrote ${changed.join(" and ")}\n`);
}
