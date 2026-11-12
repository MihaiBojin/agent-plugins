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

/**
 * The rules that dialogue and technical-writing both carry.
 *
 * A plugin cannot read another plugin's files, so each one ships its own copy.
 * A shared rule is a "### `id`" heading in the "Shared rules" section of
 * technical-writing's SKILL.md, and the first line under that heading has to
 * be dialogue's description of the guideline with that ID, word for word.
 * The WARNING and CAUTION definitions under `warnings` have to match the
 * meanings in dialogue's signals.json the same way.
 */
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIALOGUE = path.join(ROOT, "plugins/dialogue/skills/dialogue");
const SKILL = path.join(
  ROOT,
  "plugins/technical-writing/skills/technical-writing/SKILL.md",
);

/** The text under a "## name" heading, up to the next "## " heading. */
export function section(markdown, name) {
  const lines = markdown.split("\n");
  const start = lines.findIndex((line) => line.trim() === `## ${name}`);
  if (start === -1) {
    return null;
  }
  const end = lines.findIndex(
    (line, index) => index > start && line.startsWith("## "),
  );
  return lines.slice(start + 1, end === -1 ? undefined : end).join("\n");
}

/** Each "### `id`" heading, with the first non-blank line under it. */
export function rules(text) {
  const lines = text.split("\n");
  const found = [];
  lines.forEach((line, index) => {
    const heading = /^### `([a-z_]+)`\s*$/.exec(line);
    if (heading) {
      const next = lines
        .slice(index + 1)
        .find((candidate) => candidate.trim() !== "");
      const first = next === undefined || next.startsWith("#") ? "" : next;
      found.push({ id: heading[1], line: first.trim() });
    }
  });
  return found;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.join(DIALOGUE, file), "utf8"));
}

const guidelines = new Map(
  readJson("guidelines.json").map((entry) => [entry.id, entry.description]),
);
const levels = new Map(
  readJson("signals.json").intents.map((intent) => [intent.id, intent.meaning]),
);
const shared = section(fs.readFileSync(SKILL, "utf8"), "Shared rules") ?? "";

describe("rules", () => {
  it("reads the first line under each heading, past blank lines", () => {
    expect(rules("### `a_b`\n\nLine one.\nMore.\n\n### `c`\nLine c.")).toEqual([
      { id: "a_b", line: "Line one." },
      { id: "c", line: "Line c." },
    ]);
  });

  it("gives a heading with no line under it an empty one", () => {
    expect(rules("### `a`\n\n### `b`\n")).toEqual([
      { id: "a", line: "" },
      { id: "b", line: "" },
    ]);
  });
});

describe("the rules dialogue and technical-writing share", () => {
  it("technical-writing lists them under Shared rules, once each", () => {
    const ids = rules(shared).map((rule) => rule.id);
    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it.each(rules(shared))("$id has dialogue's line", ({ id, line }) => {
    expect(guidelines.has(id)).toBe(true);
    expect(line).toBe(guidelines.get(id));
  });

  it.each(["WARNING", "CAUTION"])("%s has dialogue's definition", (level) => {
    expect(levels.has(level)).toBe(true);
    expect(shared.split("\n")).toContain(`- ${level}: ${levels.get(level)}`);
  });
});
