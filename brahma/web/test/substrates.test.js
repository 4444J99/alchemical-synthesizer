"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

test("Tree loads the same substrate contracts that AdamKadmon consumes", async () => {
  const source = fs.readFileSync(path.join(__dirname, "../public/tree/substrates.js"), "utf8");
  const substrates = vm.runInNewContext(source + ";Substrates", {});
  await substrates.loadContracts(async url => ({
    ok: true,
    json: async () => JSON.parse(fs.readFileSync(path.join(__dirname, "../../substrate", path.basename(url)), "utf8"))
  }));
  for (const substrate of substrates.LIST) {
    assert.equal(substrate.contract.name, substrate.id + "_v1");
    assert.equal(substrate.contract.requiredKeys.length, 4);
    assert.deepEqual(Array.from(substrate.axes), Array.from(substrate.contract.axes));
    assert.ok(substrate.organisms.length > 0);
  }
});
