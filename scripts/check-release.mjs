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

const CHANGELOG = "CHANGELOG.md";

/**
 * A plugin that changed declares the release: a new version, and a changelog
 * section carrying it.
 *
 * The plugins are written here and the merge is the release, so an edit is
 * just a commit - which means the only place either rule can be enforced is
 * the diff.
 *
 * The version is what a client compares to decide whether an update exists, so
 * a fix shipped under the old number reaches nobody, quietly, on every machine
 * that already had it. The changelog is where the reasoning lives: what a
 * later change needs and cannot get from the diff is the alternative that was
 * weighed and dropped, written while somebody still remembers it.
 *
 *     node scripts/check-release.mjs --base origin/main
 */
export function checkRelease({ root = REPOSITORY_ROOT, base, git = run } = {}) {
  const marketplace = path.resolve(root);
  const directory = path.join(marketplace, PLUGINS_DIR);
  const errors = [];
  const released = [];

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

    const now = JSON.parse(
      fs.readFileSync(path.join(directory, name, CLAUDE_MANIFEST), "utf8"),
    ).version;

    const before = git(marketplace, [
      "show",
      `${base}:${relative}/${CLAUDE_MANIFEST}`,
    ]);
    if (before.status !== 0) {
      // Not there at the base commit, so this is a new plugin and its first
      // version is whatever it says.
      released.push(`${name} is new, at ${now}`);
    } else {
      const was = JSON.parse(before.stdout).version;
      if (compareVersions(now, was) > 0) {
        released.push(`${name} ${was} -> ${now}`);
      } else {
        errors.push(
          `${relative}/ changed but its version is still ${now}. Somebody has ${was} installed, ` +
            "and a client compares versions to decide whether an update exists - so bump it in both manifests.",
        );
        continue;
      }
    }

    const error = missingEntry(path.join(directory, name), relative, now);
    if (error) {
      errors.push(error);
    }
  }

  return { errors, released };
}

/** The complaint about `<plugin>/CHANGELOG.md`, or null when it carries the version. */
function missingEntry(directory, relative, version) {
  const file = path.join(directory, CHANGELOG);
  if (!fs.existsSync(file)) {
    return (
      `${relative}/ is at ${version} and has no ${CHANGELOG}. A release writes itself into ` +
      `${relative}/${CHANGELOG}, newest first: what changed, and the choices behind it.`
    );
  }
  if (carries(fs.readFileSync(file, "utf8"), version)) {
    return null;
  }
  return (
    `${relative}/${CHANGELOG} has no section for ${version}. Add one before the older releases: ` +
    "what changed, and the reason not to act that a later change cannot get from the diff."
  );
}

/** Whether a changelog opens a section for this version, dated or bare. */
function carries(text, version) {
  const escaped = version.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^##\\s+v?${escaped}(\\s|$)`, "m").test(text);
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
      "check-release: --base <ref> is required, e.g. --base origin/main\n",
    );
    process.exit(2);
  }

  const { errors, released } = checkRelease(values);
  for (const line of released) {
    process.stdout.write(`${line}\n`);
  }
  if (errors.length > 0) {
    process.stderr.write("Release check failed:\n");
    for (const error of errors) {
      process.stderr.write(`- ${error}\n`);
    }
    process.exit(1);
  }
  process.stdout.write(
    released.length === 0
      ? "No plugin changed\n"
      : "Every changed plugin declared its release\n",
  );
}
