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

/**
 * Throwaway marketplaces.
 *
 * Every check worth having here is about a second plugin: whether editing one
 * disturbs another's entry, its position, or its files. So the fixtures make it
 * cheap to have two.
 */

export function temporary(prefix) {
  return fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), `${prefix}-`)));
}

export function write(root, relative, contents) {
  const file = path.join(root, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, contents);
  return file;
}

export function writeJson(root, relative, value) {
  return write(root, relative, `${JSON.stringify(value, null, 2)}\n`);
}

export function readJson(root, relative) {
  return JSON.parse(fs.readFileSync(path.join(root, relative), "utf8"));
}

/** An empty marketplace, as this repository looked before its first plugin. */
export function marketplace(overrides = {}) {
  const root = temporary("marketplace");
  writeJson(root, ".claude-plugin/marketplace.json", {
    name: overrides.name ?? "MihaiBojin",
    owner: { name: "Mihai Bojin", url: "https://github.com/MihaiBojin" },
    description: "Mihai Bojin's personal plugins for coding agents",
    plugins: [],
  });
  writeJson(root, ".agents/plugins/marketplace.json", {
    name: overrides.name ?? "MihaiBojin",
    interface: { displayName: overrides.name ?? "MihaiBojin" },
    plugins: [],
  });
  return root;
}

/** A plugin written into `plugins/<name>/`, the way somebody would author one. */
export function plugin(root, name, overrides = {}) {
  const at = `plugins/${name}`;
  const version = overrides.version ?? "1.0.0";
  const description = overrides.description ?? `The ${name} plugin`;

  writeJson(root, `${at}/.claude-plugin/plugin.json`, {
    name,
    version,
    description,
    author: { name: "Mihai Bojin", url: "https://github.com/MihaiBojin" },
    homepage: `https://github.com/MihaiBojin/agent-plugins/tree/main/plugins/${name}#readme`,
    repository: "https://github.com/MihaiBojin/agent-plugins",
    license: "Apache-2.0",
    keywords: [name],
    ...(overrides.claude ?? {}),
  });
  writeJson(root, `${at}/.codex-plugin/plugin.json`, {
    name,
    version,
    description,
    author: { name: "Mihai Bojin" },
    license: "Apache-2.0",
    skills: "./skills/",
    commands: "./commands/",
    interface: {
      displayName: name,
      shortDescription: description,
      longDescription: description,
      category: "Developer Tools",
      ...(overrides.face ?? {}),
    },
    ...(overrides.codex ?? {}),
  });
  write(root, `${at}/LICENSE`, "Apache-2.0\n");
  write(root, `${at}/README.md`, `# ${name}\n`);
  write(
    root,
    `${at}/commands/${name}.md`,
    `---\nname: ${name}\ndescription: ${description}\n---\n`,
  );
  write(
    root,
    `${at}/commands/help.md`,
    `---\nname: help\ndescription: What this does\n---\n\n- /${name}:${name} - do the thing\n`,
  );
  write(
    root,
    `${at}/skills/${name}/SKILL.md`,
    `---\nname: ${name}\ndescription: ${description}\n---\n`,
  );
  for (const [relative, contents] of Object.entries(overrides.files ?? {})) {
    write(root, `${at}/${relative}`, contents);
  }
  return path.join(root, at);
}
