"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const ROOT = path.resolve(__dirname, "../../..");
function model() {
  const file = path.join(__dirname, "../public/instrument/material-model.js");
  assert.ok(fs.existsSync(file), "shared material model must exist");
  return require(file);
}
const water = phase => ({ schema: "brahma.material-state.v1", modelVersion: 1,
  phase, amount: 1, composition: [{ id: "water", fraction: 1 }] });

test("material composition rejects invalid matter rather than silently changing the sound", () => {
  const M = model();
  for (const mutate of [s => { s.phase = "fire"; }, s => { s.modelVersion = 2; },
    s => { s.amount = Infinity; }, s => { s.composition[0].fraction = .9; },
    s => { s.composition[0].id = "unknown"; }, s => { s.composition.push({ id: "water", fraction: 0 }); },
    s => { s.composition[0].fraction = true; }]) {
    const state = water("liquid"); mutate(state); assert.throws(() => M.validate(state), /material|phase|composition|fraction|version|amount/i);
  }
  assert.deepEqual(M.validate(water("liquid")), water("liquid"));
});

test("phase changes real organism controls while zero amount preserves the base recipe", () => {
  const M = model(), base = { observe: .5, assume: .5, mutate: .1 };
  const solid = M.resolve("ditto_morphic_core", base, water("solid"));
  const gas = M.resolve("ditto_morphic_core", base, water("gas"));
  assert.ok(solid.params.observe < gas.params.observe);
  assert.ok(solid.params.assume > gas.params.assume);
  assert.deepEqual(M.resolve("ditto_morphic_core", base, { ...water("gas"), amount: 0 }).params, base);
  assert.deepEqual(base, { observe: .5, assume: .5, mutate: .1 });
  assert.throws(() => M.resolve("unknown_module", {}, water("solid")), /mapping|unsupported/i);
  assert.throws(() => M.resolve("ditto_morphic_core", { observe: 2 }, water("solid")), /control|range/i);
});

test("mixture order canonicalizes and extreme material settings stay inside native control ranges", () => {
  const M = model();
  const mix = { ...water("liquid"), composition: [{ id: "water", fraction: .25 }, { id: "iron", fraction: .75 }] };
  const backwards = { ...mix, composition: [...mix.composition].reverse() };
  assert.deepEqual(M.resolve("agent_smith_identity", {}, mix), M.resolve("agent_smith_identity", {}, backwards));
  for (const module of Object.keys(M.payload.library.profiles)) {
    const result = M.resolve(module, {}, water("gas"));
    for (const [key, value] of Object.entries(result.params)) {
      const [, min, max, step] = M.payload.controls[module][key];
      assert.ok(value >= min && value <= max, module + ":" + key);
      if (step === 1) assert.ok(Number.isInteger(value));
    }
  }
});

test("Nucleus persistence switches between retained playback and its native muted recording state", () => {
  const M = model();
  assert.equal(M.resolve("nucleus_freeze", {}, water("solid")).params.freeze, 1);
  assert.equal(M.resolve("nucleus_freeze", {}, water("gas")).params.freeze, 0);
  assert.equal(M.resolve("nucleus_freeze", {}, { ...water("gas"), amount: 0 }).params.freeze, 1);
});

test("Node/browser and native Python use identical material properties, mappings and model identity", () => {
  const M = model();
  const cases = ["solid", "liquid", "gas"].map(phase => ["ditto_morphic_core", { observe: .5 }, water(phase)]);
  cases.push(["mnemosyne_voice_stereo", { age: .1 }, { ...water("liquid"), composition: [{ id: "water", fraction: .4 }, { id: "silica", fraction: .6 }] }]);
  for (const phase of ["solid", "liquid", "gas"]) cases.push(["nucleus_freeze", {}, water(phase)]);
  const script = "import json,sys; from forge.materials import resolve; print(json.dumps([resolve(*case) for case in json.load(sys.stdin)]))";
  const native = JSON.parse(execFileSync("python3", ["-c", script], { cwd: ROOT, input: JSON.stringify(cases), encoding: "utf8" }));
  assert.deepEqual(native, cases.map(args => M.resolve(...args)));
});
