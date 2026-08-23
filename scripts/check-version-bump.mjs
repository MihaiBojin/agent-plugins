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
import { spawnSync } from "node:child_process";
import { parseArgs } from "node:util";
import { CLAUDE_MANIFEST, PLUGINS_DIR, compareVersions } from "./catalogs.mjs";
import { REPOSITORY_ROOT } from "./validate-plugin.mjs";

/**
 * A plugin that changed has to say so in its version.
 *
 * The plugins are written here and the merge is the release, so an edit is
 * just a commit - which means the only place this rule can still be enforced
 * is the diff.
 *
 * Without it the failure is quiet and permanent: a client that has 0.1.0
 * compares versions to decide whether an update exists, finds the same number,
 * and never fetches the fix. Nobody sees an error; the plugin is simply wrong
 * on every machine that already had it.
 *
 *     node scripts/check-version-bump.mjs --base origin/main
 */
export function checkVersionBump({
  root = REPOSITORY_ROOT,
  base,
  git = run,
} = {}) {
  const marketplace = path.resolve(root);
  const directory = path.join(marketplace, PLUGINS_DIR);
  const errors = [];
  const bumped = [];

  const plugins = fs.existsSync(directory)
    ? fs
        .readdirSync(directory, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name)
        .sort()
    : [];

  for (const name of plugins) {
    const relative = `${PLUGINS_DIR}/${name}`;
    const diff = git(marketplace, [
      "diff",
      "--name-only",
      base,
      "--",
      relative,
    ]);
    if (diff.status !== 0) {
      errors.push(`cannot compare against ${base}: ${diff.stderr.trim()}`);
      continue;
    }
    if (diff.stdout.trim() === "") {
      continue;
    }

    const before = git(marketplace, [
      "show",
      `${base}:${relative}/${CLAUDE_MANIFEST}`,
    ]);
    if (before.status !== 0) {
      // Not there at the base commit, so this is a new plugin and its first
      // version is whatever it says.
      bumped.push(`${name} is new`);
      continue;
    }

    const was = JSON.parse(before.stdout).version;
    const now = JSON.parse(
      fs.readFileSync(path.join(directory, name, CLAUDE_MANIFEST), "utf8"),
    ).version;

    if (compareVersions(now, was) > 0) {
      bumped.push(`${name} ${was} -> ${now}`);
      continue;
    }
    errors.push(
      `${relative}/ changed but its version is still ${now}. Somebody has ${was} installed, ` +
        "and a client compares versions to decide whether an update exists - so bump it in both manifests.",
    );
  }

  return { errors, bumped };
}

function run(cwd, args) {
  const result = spawnSync("git", args, { cwd, encoding: "utf8" });
  return {
    status: result.status,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

// Run directly, rather than imported by a test.
if (
  process.argv[1] &&
  import.meta.url.endsWith(path.basename(process.argv[1]))
) {
  const { values } = parseArgs({
    options: { root: { type: "string" }, base: { type: "string" } },
  });
  if (!values.base) {
    process.stderr.write(
      "check-version-bump: --base <ref> is required, e.g. --base origin/main\n",
    );
    process.exit(2);
  }

  const { errors, bumped } = checkVersionBump(values);
  for (const line of bumped) {
    process.stdout.write(`${line}\n`);
  }
  if (errors.length > 0) {
    process.stderr.write("Version check failed:\n");
    for (const error of errors) {
      process.stderr.write(`- ${error}\n`);
    }
    process.exit(1);
  }
  process.stdout.write(
    bumped.length === 0
      ? "No plugin changed\n"
      : "Every changed plugin was bumped\n",
  );
}
