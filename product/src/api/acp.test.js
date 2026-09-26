"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { interpret } = require("./acp");

test("ACP keeps structured directives and command precedence", () => {
  const cases = [
    ['{"action":"render_specimen","args":{"module":"Azoth"}}', "render_specimen", { module: "Azoth" }],
    ["list specimen", "list_specimens", {}],
    ["show module catalog", "list_modules", {}],
    ["render from the azoth", "render_specimen", { module: "Azoth" }],
    ["render a specimen of nebula", "render_specimen", { module: "Nebula" }],
    ["render the azoth", "render_specimen", { module: "Azoth" }],
    ["module granular", "list_modules", { q: "granular" }],
    ["module old module new", "list_modules", { q: "new" }],
    ["render azoth status", "get_organism_state", {}],
    ["specimens list", "list_modules", {}],
    ["list\nspecimens", "list_modules", {}],
    ["render azoth\nrender from nebula", "render_specimen", { module: "Nebula" }],
    ["render from\nrender from nebula", "render_specimen", { module: "Nebula" }],
    ["render from\n the azoth", "render_specimen", { module: "Azoth" }],
    ["from render of azoth", "render_specimen", { module: "Azoth" }],
    ["module old\nmodule new", "list_modules", { q: "old\nmodule new" }],
    ["hello", "list_modules", {}]
  ];
  for (const [prompt, action, args] of cases) assert.deepEqual(interpret(prompt), { action, args }, prompt);
});

test("repeated command words and absent suffixes finish within a bounded process", () => {
  const code = `const {interpret}=require(${JSON.stringify(require.resolve("./acp"))});
    for (const word of ["list ","show ","render ","modulex "]) {
      interpret(word.repeat(50000));
    }`;
  const result = spawnSync(process.execPath, ["-e", code], { timeout: 3000, encoding: "utf8" });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
});
