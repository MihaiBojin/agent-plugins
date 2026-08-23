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
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import {
  CLAUDE_CATALOG,
  CLAUDE_MANIFEST,
  CODEX_CATALOG,
  CODEX_MANIFEST,
  MARKETPLACE_NAME,
  PLUGINS_DIR,
  PLUGIN_NAME,
  SEMVER,
  claudeEntry,
  claudeSource,
  codexEntry,
  codexSource,
  serializeJson,
} from "./catalogs.mjs";

/**
 * The invariants that hold between the two catalogs, which neither client's
 * own validator can see.
 *
 * Claude Code reads one file and Codex reads another. Each is happy on its own
 * with an inventory the other does not have, so the failure this exists to
 * catch is a marketplace that installs a different set of plugins - or a
 * different version of one - depending on which agent you asked. Both files are
 * generated, so any disagreement between them is a bug in the generator or an
 * edit somebody made by hand.
 */

const CATALOGS = [
  ["Claude Code", CLAUDE_CATALOG],
  ["Codex", CODEX_CATALOG],
];

/**
 * Files that have no business in a published plugin.
 *
 * A plugin directory is edited here like any other source, and unpacked by an
 * agent host that reads everything it finds. Neither a reviewer skimming a
 * diff nor that host is going to ask why there is a `.env` in it.
 */
const FORBIDDEN_NAMES = [
  /^\.env(\..+)?$/,
  /^\.npmrc$/,
  /^\.netrc$/,
  /^\.git$/,
  /^\.DS_Store$/,
  /^node_modules$/,
  /^id_(rsa|dsa|ecdsa|ed25519)$/,
  /\.(pem|key|p12|pfx|keystore|jks)$/,
];

const SECRET_PATTERNS = [
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "a private key"],
  [
    /\b(?:postgres|postgresql|mysql|mongodb(?:\+srv)?|redis|amqp):\/\/[^\s/:@]+:[^\s/@]+@/,
    "a connection string with a password",
  ],
  [/\bghp_[A-Za-z0-9]{36}\b/, "a GitHub personal access token"],
  [/\bgithub_pat_[A-Za-z0-9_]{22,}\b/, "a GitHub fine-grained token"],
  [/\bAKIA[0-9A-Z]{16}\b/, "an AWS access key id"],
  [/\bxox[baprs]-[A-Za-z0-9-]{10,}/, "a Slack token"],
  [/\bsk-ant-[A-Za-z0-9_-]{20,}/, "an Anthropic API key"],
];

/** The checkout this script ships in, so it validates the right tree. */
export const REPOSITORY_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

export function validateMarketplaces({ root = REPOSITORY_ROOT } = {}) {
  const errors = [];
  const marketplace = path.resolve(root);

  const catalogs = {};
  for (const [client, relative] of CATALOGS) {
    catalogs[relative] = readCatalog(marketplace, client, relative, errors);
  }

  const claude = catalogs[CLAUDE_CATALOG];
  const codex = catalogs[CODEX_CATALOG];
  if (!claude || !codex) {
    return { plugins: [], errors };
  }

  const names = pluginNames(claude, CLAUDE_CATALOG, errors);
  pluginNames(codex, CODEX_CATALOG, errors);

  // Same inventory, same order. Order is what Codex renders by, and a
  // marketplace whose two halves disagree about which plugins exist is one
  // where the answer to "is that plugin available?" depends on the client.
  const claudeOrder = claude.plugins.map((entry) => entry?.name).join(", ");
  const codexOrder = codex.plugins.map((entry) => entry?.name).join(", ");
  if (claudeOrder !== codexOrder) {
    errors.push(
      `the catalogs list different plugins: ${CLAUDE_CATALOG} has [${claudeOrder}], ` +
        `${CODEX_CATALOG} has [${codexOrder}]`,
    );
  }

  for (const name of names) {
    validatePlugin(marketplace, name, claude, codex, errors);
  }

  validateNoOrphans(marketplace, names, errors);
  validateStableJson(marketplace, errors);

  return { plugins: names, errors };
}

function readCatalog(marketplace, client, relative, errors) {
  const file = path.join(marketplace, relative);
  let value;
  try {
    value = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    errors.push(`cannot read ${relative}: ${error.message}`);
    return null;
  }
  if (value.name !== MARKETPLACE_NAME) {
    errors.push(
      `${relative} names the marketplace '${value.name}', but ${client} users install ` +
        `from '${MARKETPLACE_NAME}'`,
    );
  }
  if (!Array.isArray(value.plugins)) {
    errors.push(`${relative} has no plugins array`);
    return null;
  }
  return value;
}

function pluginNames(catalog, relative, errors) {
  const names = [];
  const seen = new Set();
  for (const entry of catalog.plugins) {
    const name = entry?.name;
    if (typeof name !== "string" || !PLUGIN_NAME.test(name)) {
      errors.push(
        `${relative} has an entry named '${name}', which is not a usable plugin name`,
      );
      continue;
    }
    if (seen.has(name)) {
      errors.push(`${relative} lists '${name}' twice`);
      continue;
    }
    seen.add(name);
    names.push(name);
  }
  return names;
}

function validatePlugin(marketplace, name, claude, codex, errors) {
  const directory = path.join(marketplace, PLUGINS_DIR, name);
  const listedClaude = claude.plugins.find((entry) => entry?.name === name);
  const listedCodex = codex.plugins.find((entry) => entry?.name === name);

  // Path traversal, checked against the resolved path rather than the string:
  // `./plugins/../../etc` and `./plugins/docket/../../..` both read as being
  // under plugins/ until they are resolved. This runs before the entries are
  // compared as a whole, so an escaping source is reported as what it is.
  for (const [relative, source] of [
    [CLAUDE_CATALOG, listedClaude?.source],
    [CODEX_CATALOG, listedCodex?.source?.path],
  ]) {
    if (typeof source === "string" && !resolvesInside(marketplace, source)) {
      errors.push(
        `${relative} entry '${name}' points outside ${PLUGINS_DIR}/: ${source}`,
      );
    }
  }
  if (serializeJson(listedCodex?.source) !== serializeJson(codexSource(name))) {
    errors.push(
      `${CODEX_CATALOG} entry '${name}' does not have a local source at './${PLUGINS_DIR}/${name}'`,
    );
  }
  if (listedClaude?.source !== claudeSource(name)) {
    errors.push(
      `${CLAUDE_CATALOG} entry '${name}' has source '${listedClaude?.source}', ` +
        `expected '${claudeSource(name)}'`,
    );
  }
  if (
    !listedCodex?.policy?.installation ||
    !listedCodex?.policy?.authentication
  ) {
    errors.push(
      `${CODEX_CATALOG} entry '${name}' has no installation and authentication policy`,
    );
  }
  if (
    typeof listedCodex?.category !== "string" ||
    listedCodex.category.trim() === ""
  ) {
    errors.push(`${CODEX_CATALOG} entry '${name}' has no category`);
  }

  if (!fs.existsSync(directory)) {
    errors.push(
      `${PLUGINS_DIR}/${name}/ is in both catalogs but not in the repository`,
    );
    return;
  }

  const manifests = {};
  for (const [client, relative] of [
    ["claude", CLAUDE_MANIFEST],
    ["codex", CODEX_MANIFEST],
  ]) {
    const file = path.join(directory, relative);
    try {
      manifests[client] = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (error) {
      errors.push(
        `cannot read ${PLUGINS_DIR}/${name}/${relative}: ${error.message}`,
      );
    }
  }
  if (!manifests.claude || !manifests.codex) {
    return;
  }

  for (const [manifest, relative] of [
    [manifests.claude, CLAUDE_MANIFEST],
    [manifests.codex, CODEX_MANIFEST],
  ]) {
    if (manifest.name !== name) {
      errors.push(
        `${PLUGINS_DIR}/${name}/${relative} names the plugin '${manifest.name}'`,
      );
    }
    if (
      typeof manifest.version !== "string" ||
      !SEMVER.test(manifest.version)
    ) {
      errors.push(
        `${PLUGINS_DIR}/${name}/${relative} version must be strict X.Y.Z semver`,
      );
    }
  }
  if (manifests.claude.version !== manifests.codex.version) {
    errors.push(
      `${PLUGINS_DIR}/${name}/ carries two versions: ${CLAUDE_MANIFEST} is ` +
        `${manifests.claude.version}, ${CODEX_MANIFEST} is ${manifests.codex.version}`,
    );
  }

  // The catalog is what a client reads before it fetches anything, so a
  // version there that is not the version in the plugin is an update nobody
  // gets, or one that arrives and installs the same files again.
  if (listedClaude?.version !== manifests.claude.version) {
    errors.push(
      `${CLAUDE_CATALOG} lists ${name} ${listedClaude?.version}, but the plugin is ` +
        `${manifests.claude.version}`,
    );
  }

  // Both entries are generated from those manifests, so anything else in them
  // was typed by a person - and a description or a licence that only the
  // catalog knows about is one nothing downstream will ever correct.
  for (const [relative, listed, expected] of [
    [CLAUDE_CATALOG, listedClaude, claudeEntry(manifests.claude)],
    [CODEX_CATALOG, listedCodex, codexEntry(manifests.codex)],
  ]) {
    if (serializeJson(listed) !== serializeJson(expected)) {
      errors.push(
        `${relative} entry '${name}' is not what the publisher generates from ` +
          `${PLUGINS_DIR}/${name}; run the publisher rather than editing it`,
      );
    }
  }

  validateContents(marketplace, directory, errors);
}

function validateContents(marketplace, directory, errors) {
  const stack = [directory];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch (error) {
      errors.push(
        `cannot read ${path.relative(marketplace, current)}: ${error.message}`,
      );
      continue;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      const relative = path.relative(marketplace, full);

      if (FORBIDDEN_NAMES.some((pattern) => pattern.test(entry.name))) {
        errors.push(`${relative} does not belong in a published plugin`);
        continue;
      }
      if (entry.isDirectory()) {
        stack.push(full);
        continue;
      }
      if (!entry.isFile()) {
        errors.push(
          `${relative} is not a regular file; a published plugin has no symlinks`,
        );
        continue;
      }

      const contents = fs.readFileSync(full);
      // A binary file is not something this marketplace publishes, and it is
      // also the shape a leaked keystore or database dump arrives in.
      if (contents.includes(0)) {
        errors.push(`${relative} is binary; a published plugin is text`);
        continue;
      }
      const text = contents.toString("utf8");
      for (const [pattern, what] of SECRET_PATTERNS) {
        if (pattern.test(text)) {
          errors.push(`${relative} looks like it contains ${what}`);
        }
      }
    }
  }
}

/** A directory under `plugins/` that no catalog mentions installs for nobody. */
function validateNoOrphans(marketplace, names, errors) {
  const directory = path.join(marketplace, PLUGINS_DIR);
  if (!fs.existsSync(directory)) {
    return;
  }
  const listed = new Set(names);
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.name === ".gitkeep") {
      // What keeps plugins/ in git until the first plugin lands.
      continue;
    }
    if (!entry.isDirectory()) {
      errors.push(`${PLUGINS_DIR}/${entry.name} is not a plugin directory`);
    } else if (!listed.has(entry.name)) {
      errors.push(
        `${PLUGINS_DIR}/${entry.name}/ is in the repository but in neither catalog`,
      );
    }
  }
}

/**
 * Both catalogs are generated, so both must already be in generated form.
 *
 * Otherwise the next publication rewrites lines nobody touched, the diff stops
 * being reviewable, and somebody eventually fixes the noise by editing the
 * generated file - at which point it is no longer generated.
 */
function validateStableJson(marketplace, errors) {
  for (const [, relative] of CATALOGS) {
    const file = path.join(marketplace, relative);
    const text = fs.readFileSync(file, "utf8");
    if (text !== serializeJson(JSON.parse(text))) {
      errors.push(
        `${relative} is not in the form the publisher writes; run the publisher rather than editing it`,
      );
    }
  }
}

function resolvesInside(marketplace, source) {
  const plugins = path.resolve(marketplace, PLUGINS_DIR);
  const resolved = path.resolve(marketplace, source);
  const relative = path.relative(plugins, resolved);
  return (
    relative !== "" && !relative.startsWith("..") && !path.isAbsolute(relative)
  );
}

// Run directly, rather than imported by a test.
if (
  process.argv[1] &&
  import.meta.url.endsWith(path.basename(process.argv[1]))
) {
  const { values } = parseArgs({ options: { root: { type: "string" } } });
  const { plugins, errors } = validateMarketplaces(values);

  if (errors.length > 0) {
    process.stderr.write("Marketplace validation failed:\n");
    for (const error of errors) {
      process.stderr.write(`- ${error}\n`);
    }
    process.exit(1);
  }
  process.stdout.write(
    plugins.length === 0
      ? "Marketplace validation passed (no plugins published yet)\n"
      : `Marketplace validation passed (${plugins.join(", ")})\n`,
  );
}
