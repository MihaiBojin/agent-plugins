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
import {
  parseStrictJson,
  validatePlugin,
} from "../scripts/validate-plugin.mjs";

/**
 * A plugin is a directory two different agents read, and neither says anything
 * when the packaging is wrong: a skill they cannot find is indistinguishable
 * from a skill the model chose not to use. These are the mistakes that would
 * otherwise be discovered by somebody asking for the plugin's help and getting
 * a conversation instead.
 */

const MANIFEST = {
  name: "docket",
  version: "0.1.0",
  description: "Shepherd documents through review",
};

function plugin(overrides = {}) {
  const root = path.join(
    fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "plugin-"))),
    "docket",
  );
  fs.mkdirSync(root);
  const write = (relative, contents) => {
    fs.mkdirSync(path.join(root, path.dirname(relative)), { recursive: true });
    fs.writeFileSync(path.join(root, relative), contents);
  };

  const claude = { ...MANIFEST, ...(overrides.claude ?? {}) };
  const codex = {
    ...MANIFEST,
    skills: "./skills/",
    commands: "./commands/",
    interface: {
      displayName: "docket",
      shortDescription: "Document lifecycles",
      longDescription: "Document lifecycles, from draft to frozen snapshot",
      category: "Developer Tools",
      ...(overrides.face ?? {}),
    },
    ...(overrides.codex ?? {}),
  };

  write(".claude-plugin/plugin.json", JSON.stringify(claude));
  write(".codex-plugin/plugin.json", JSON.stringify(codex));
  write(
    `skills/${overrides.skillDirectory ?? "docket"}/SKILL.md`,
    `---\nname: ${overrides.skillName ?? "docket"}\ndescription: Moves documents\n---\n\n# docket\n`,
  );
  write("skills/docket/helper.mjs", "// helper\n");
  write(
    "commands/freeze.md",
    `---\nname: ${overrides.commandName ?? "freeze"}\ndescription: ${overrides.commandDescription ?? "Freeze a document"}\n---\n\nFreeze $ARGUMENTS.\n`,
  );
  write(
    "commands/help.md",
    `---\nname: help\ndescription: What this plugin does\n---\n\n- ${overrides.helpLists ?? "/docket:freeze"} - freeze a document\n`,
  );
  write(
    "hooks/hooks.json",
    JSON.stringify({
      hooks: {
        UserPromptSubmit: [
          {
            hooks: [
              {
                type: "command",
                command: `node "\${CLAUDE_PLUGIN_ROOT}/${overrides.hookTarget ?? "skills/docket/helper.mjs"}" nudge`,
              },
            ],
          },
        ],
      },
    }),
  );

  return root;
}

describe("validatePlugin", () => {
  const roots = [];

  const build = (overrides) => {
    const root = plugin(overrides);
    roots.push(root);
    return root;
  };

  afterEach(() => {
    for (const root of roots.splice(0)) {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });

  it("accepts a well-formed plugin", () => {
    expect(validatePlugin({ root: build() }).errors).toEqual([]);
  });

  it("accepts native skills without a commands declaration or directory", () => {
    const root = build({ codex: { commands: undefined } });
    fs.rmSync(path.join(root, "commands"), { recursive: true });
    fs.appendFileSync(
      path.join(root, "skills", "docket", "SKILL.md"),
      "\nRun `${CLAUDE_PLUGIN_ROOT}/skills/docket/helper.mjs`.\n",
    );

    expect(validatePlugin({ root }).errors).toEqual([]);
  });

  it("catches a native skill naming a script that is not shipped", () => {
    const root = build({ codex: { commands: undefined } });
    fs.rmSync(path.join(root, "commands"), { recursive: true });
    fs.appendFileSync(
      path.join(root, "skills", "docket", "SKILL.md"),
      '\nRun `node "${CLAUDE_PLUGIN_ROOT}/skills/docket/missing.mjs"`.\n',
    );

    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining(
        "skills/docket/SKILL.md references a missing file",
      ),
    ]);
  });

  it("catches manifests that have drifted apart", () => {
    const root = build({ codex: { version: "0.2.0" } });
    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("manifest versions differ"),
    ]);
  });

  it("catches a version that does not match the release being cut", () => {
    const root = build();
    expect(validatePlugin({ root, expected: "9.9.9" }).errors).toHaveLength(2);
  });

  it("catches Codex being pointed somewhere other than skills/", () => {
    const root = build({ codex: { skills: "./.codex-plugin/skills/" } });
    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining('"skills": "./skills/"'),
    ]);
  });

  it("catches a skill whose front matter disagrees with its directory", () => {
    const root = build({ skillName: "documents" });
    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("is named 'documents'"),
    ]);
  });

  it("catches a hook pointing at a script that moved", () => {
    const root = build({ hookTarget: "skills/docket/moved.mjs" });
    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("references a missing file"),
    ]);
  });

  it("catches a second copy of a skill under a product directory", () => {
    const root = build();
    fs.mkdirSync(path.join(root, ".codex-plugin", "skills", "docket"), {
      recursive: true,
    });
    fs.writeFileSync(
      path.join(root, ".codex-plugin", "skills", "docket", "SKILL.md"),
      "---\nname: docket\ndescription: a divergent copy\n---\n",
    );
    expect(validatePlugin({ root }).errors).toEqual(
      expect.arrayContaining([
        expect.stringContaining(".codex-plugin/skills must not exist"),
        expect.stringContaining("duplicates a skill"),
      ]),
    );
  });

  it("catches a command whose front matter disagrees with its filename", () => {
    const root = build({ commandName: "archive" });
    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("commands/freeze.md is named 'archive'"),
    ]);
  });

  it("catches a command with nothing to show in the menu", () => {
    const root = build({ commandDescription: "" });
    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("commands/freeze.md has no description"),
    ]);
  });

  /**
   * A help text that omits a command is worse than none: it reads as a
   * complete list, and the command it leaves out is the one nobody finds.
   */
  it("catches a help command that has stopped listing one", () => {
    const root = build({ helpLists: "/docket:something-else" });
    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("help.md does not list /docket:freeze"),
    ]);
  });

  /**
   * A packaged command exists to be one deterministic invocation. One that
   * runs a shipped script without declaring it asks for permission every
   * time, which is the stall it was written to remove.
   */
  it("catches a command that runs a script without declaring it", () => {
    const root = build();
    fs.writeFileSync(
      path.join(root, "commands", "freeze.md"),
      "---\nname: freeze\ndescription: Freeze a document\n---\n\n" +
        'Run `node "${CLAUDE_PLUGIN_ROOT}/skills/docket/helper.mjs" freeze`.\n',
    );

    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("runs a script without allowed-tools"),
    ]);
  });

  it("catches Codex being pointed somewhere other than commands/", () => {
    const root = build({ codex: { commands: "./prompts/" } });
    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining('"commands": "./commands/"'),
    ]);
  });

  /**
   * A command names a script by an absolute path the host substitutes, so one
   * that is not in the published tree fails at the moment it is run and
   * nowhere earlier - inside a directory the user has never heard of.
   */
  it("catches a command naming a script that is not there", () => {
    const root = build();
    fs.writeFileSync(
      path.join(root, "commands", "freeze.md"),
      "---\nname: freeze\ndescription: Freeze a document\nallowed-tools: Bash\n---\n" +
        'Run `node "${CLAUDE_PLUGIN_ROOT}/skills/docket/moved.mjs" freeze`.\n',
    );

    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("commands/freeze.md references a missing file"),
    ]);
  });

  it("catches a commands directory that is not there at all", () => {
    const root = build();
    fs.rmSync(path.join(root, "commands"), { recursive: true });

    expect(validatePlugin({ root }).errors).toEqual([
      expect.stringContaining("commands/ is missing"),
    ]);
  });

  /**
   * Codex requires the interface block, and `category` is also the only place
   * the published Codex catalog entry can get a category from.
   */
  it("catches a Codex manifest with nothing to display", () => {
    expect(
      validatePlugin({ root: build({ face: { category: "" } }) }).errors,
    ).toEqual([expect.stringContaining("interface.category is missing")]);

    expect(
      validatePlugin({ root: build({ codex: { interface: undefined } }) })
        .errors,
    ).toEqual([expect.stringContaining("has no interface block")]);
  });
});

describe("parseStrictJson", () => {
  it("refuses a repeated key, which JSON.parse resolves silently", () => {
    expect(() =>
      parseStrictJson('{"version":"0.1.0","version":"0.2.0"}'),
    ).toThrow(/duplicate key 'version'/);
  });

  it("allows the same key in different objects", () => {
    expect(parseStrictJson('{"a":{"name":1},"name":2}')).toEqual({
      a: { name: 1 },
      name: 2,
    });
  });

  it("is not fooled by braces and quotes inside strings", () => {
    expect(parseStrictJson('{"a":"{\\"name\\":1}","name":2}')).toEqual({
      a: '{"name":1}',
      name: 2,
    });
  });
});
