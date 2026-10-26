"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const P = require("../public/instrument/pattern.js");
function model() {
  const filename = path.join(__dirname, "../public/instrument/sample-project.js");
  assert.ok(fs.existsSync(filename), "portable sample project model must exist");
  return require(filename);
}
async function fixture() {
  const M = model();
  const source = await M.createSource(new Uint8Array([0, 1, 2, 3]), {
    name: 'song "one" <test>.wav', mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
  });
  const scene = P.makeScene(16, 5);
  P.setCell(scene, 0, 0, { note: 60, vel: 0.8, sampleId: source.id, slice: 2 });
  return { schema: "brahma.sample-project.v1", name: "My session", tempo: 97,
    phase: "manual", cycle: 7, scene, trackSources: [source.id, null, null, null, null], sources: [source] };
}

test("portable project restores exact source bytes, chop edits, pattern and transport", async () => {
  const project = await fixture(), M = model();
  project.sources[0].slices[2] = { start: 2.1, end: 2.8 };
  const reopened = await M.deserialize(M.serialize(project));
  assert.equal(reopened.tempo, 97);
  assert.equal(reopened.cycle, 7);
  assert.deepEqual(reopened.sources[0].slices[2], { start: 2.1, end: 2.8 });
  assert.deepEqual(Array.from(M.sourceBytes(reopened.sources[0])), [0, 1, 2, 3]);
  assert.equal(reopened.scene.grid[0][0].sampleId, reopened.sources[0].id);
  assert.equal(reopened.scene.grid[0][0].slice, 2);
  assert.equal(reopened.sources[0].name, 'song "one" <test>.wav');
  assert.equal(reopened.sources[0].sha256, "054edec1d0211f624fed0cbca9d4f9400b0e491c43742af2c5b0abebf0c990d8");
});

test("equal chops cover the whole source without dropping the last region", () => {
  const slices = model().equalSlices(4, 8);
  assert.deepEqual(slices[0], { start: 0, end: 0.5 });
  assert.deepEqual(slices[7], { start: 3.5, end: 4 });
  assert.throws(() => model().equalSlices(0, 8), /duration/i);
});

test("corrupt embedded audio is rejected before it can replace a session", async () => {
  const project = await fixture();
  project.sources[0].data = "AQIDBA==";
  await assert.rejects(model().deserialize(JSON.stringify(project)), /hash|integrity/i);
});

test("source identity deduplicates identical bytes even when filenames differ", async () => {
  const a = (await fixture()).sources[0];
  const b = await model().createSource(new Uint8Array([0, 1, 2, 3]), {
    name: "renamed.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
  });
  assert.equal(a.id, b.id);
});

test("invalid source references and slice bounds cannot silently fall back to synthesis", async () => {
  const project = await fixture(), M = model();
  for (const mutate of [
    p => { p.scene.grid[0][0].sampleId = "missing"; },
    p => { p.scene.grid[0][0].slice = 8; },
    p => { p.sources[0].slices[2].end = 9; },
    p => { p.sources[0].slices[2].start = 3; },
    p => { p.trackSources[1] = "missing"; },
    p => { p.sources.push(p.sources[0]); },
    p => { p.tempo = 0; },
    p => { p.scene.grid[0][0].vel = Infinity; },
    p => { p.scene.grid.pop(); },
  ]) {
    const bad = structuredClone(project); mutate(bad);
    assert.throws(() => M.validateProject(bad), /invalid|missing|duplicate|slice|tempo|velocity|grid/i);
  }
});

test("resource budgets reject project audio before decoding and are configurable", async () => {
  const project = await fixture(), M = model();
  assert.throws(() => M.serialize(project, { maxSourceBytes: 3 }), /limit|large|budget/i);
  assert.doesNotThrow(() => M.serialize(project, { maxSourceBytes: 4 }));
  await assert.rejects(M.deserialize(" ".repeat(2000), { maxProjectBytes: 1024 }), /limit|large|budget/i);
});

test("sample references survive ratchets, stutters and every generative phase", () => {
  const scene = P.makeScene(16, 5);
  P.setCell(scene, 0, 0, { note: 60, vel: 0.8, cmd: "RT", amt: 4, sampleId: "donor", slice: 3 });
  assert.equal(scene.grid[0][0].sampleId, "donor");
  for (const cmd of ["", "RT", "ST", "OV", "HU", "DN"]) {
    const cell = { ...scene.grid[0][0], cmd, amt: cmd === "DN" ? 1 : 4 };
    for (const event of P.expandCell(cell, 0.125, P.makeRng(1))) {
      assert.equal(event.sampleId, "donor"); assert.equal(event.slice, 3);
    }
  }
  for (const phase of P.PHASES) {
    const redistributed = P.redistribute(scene, phase, 3);
    const hits = redistributed.grid.flat().filter(Boolean);
    assert.ok(hits.length > 0);
    assert.ok(hits.every(c => c.sampleId === "donor" && c.slice === 3), phase);
  }
});
