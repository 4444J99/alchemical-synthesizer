"use strict";
const { test } = require("node:test");
const fs = require("node:fs"), vm = require("node:vm"), assert = require("node:assert/strict");
test("example engine updates cannot traverse prototypes or absent properties", () => {
  const source = fs.readFileSync(require("node:path").join(__dirname, "synth-drum-machine.tsx"), "utf8");
  const code = source.slice(source.indexOf("  const updateEngine ="), source.indexOf("\n  const updateLFO"));
  let tracks = [{ engine: { osc: { gain: 1 } } }];
  const context = vm.createContext({ selectedTrack: 0, setTracks: f => { tracks = f(tracks); } });
  vm.runInContext(code + '\nupdateEngine("osc.gain", 2);', context);
  assert.equal(tracks[0].engine.osc.gain, 2);
  for (const key of ["__proto__.polluted", "constructor.prototype.polluted", "osc.__proto__.polluted", "missing.value", "osc..gain"]) {
    const old = tracks[0];
    vm.runInContext("updateEngine(" + JSON.stringify(key) + ", true)", context);
    assert.equal(tracks[0], old);
  }
  assert.equal(vm.runInContext("({}).polluted", context), undefined);
});
