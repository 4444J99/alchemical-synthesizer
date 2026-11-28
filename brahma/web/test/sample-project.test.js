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

test("native transformation recipes retain their source and exact settings after reopen", async () => {
  const project = await fixture(), M = model(), parent = project.sources[0];
  const output = await M.createSource(new Uint8Array([4, 5, 6, 7]), {
    name: "Native pitch.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
  });
  output.recipe = { schema: "brahma.native-recipe.v1", parentId: parent.id, module: "solve_pitch_shift",
    params: { semitones: -7, mix: .75 }, inputSha256: "c".repeat(64),
    definitionSha256: "a".repeat(64), rackSha256: "b".repeat(64) };
  project.sources.push(output);
  project.trackSources[0] = output.id;
  const reopened = await M.deserialize(M.serialize(project));
  assert.deepEqual(reopened.sources[1].recipe, output.recipe);
  for (const mutate of [p => { p.sources[1].recipe.parentId = "missing"; },
    p => { p.sources[1].recipe.params.semitones = Infinity; }, p => { p.sources[1].recipe.parentId = output.id; }]) {
    const bad = structuredClone(project); mutate(bad); assert.throws(() => M.validateProject(bad), /recipe|parent|control/i);
  }
});

test("replacing one track sound changes its future notes and preserves unrelated sources and chops", async () => {
  const project = await fixture(), M = model(), parent = project.sources[0];
  assert.equal(typeof M.replaceTrackSource, "function", "track replacement must be transactional");
  const next = await M.createSource(new Uint8Array([4, 5, 6, 7]), {
    name: "next.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
  });
  project.sources.push(next);
  P.setCell(project.scene, 1, 0, { note: 60, vel: .5, sampleId: parent.id, slice: 3 });
  const replaced = M.replaceTrackSource(project, 0, parent.id, next.id);
  assert.equal(replaced.scene.grid[0][0].sampleId, next.id);
  assert.equal(replaced.scene.grid[0][0].slice, 2);
  assert.equal(replaced.scene.grid[1][0].sampleId, parent.id);
  assert.equal(project.scene.grid[0][0].sampleId, parent.id);
  assert.equal(replaced.sources.length, 2);
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

test("per-track vessels survive reopen separately from the compositional arc and retained native material recipe", async () => {
  const M = model(), project = await fixture();
  const material = { schema: "brahma.material-state.v1", modelVersion: 1, phase: "solid", amount: .8,
    composition: [{ id: "water", fraction: .25 }, { id: "iron", fraction: .75 }] };
  project.vessels = [{ module: "ditto_morphic_core", params: { observe: .4, assume: .6, mutate: .1 }, material }, null, null, null, null];
  const reopened = await M.deserialize(M.serialize(project));
  assert.equal(reopened.phase, "manual");
  assert.equal(reopened.vessels[0].material.phase, "solid");
  assert.deepEqual(reopened.vessels[0].material.composition, [{ id: "iron", fraction: .75 }, { id: "water", fraction: .25 }]);
  assert.equal(reopened.vessels[1], null);
  assert.deepEqual(M.validateProject(await fixture()).vessels, [null, null, null, null, null]);
  for (const mutate of [p => { p.vessels[0].material.phase = "fire"; },
    p => { p.vessels[0].material.composition[0].fraction = .8; },
    p => { p.vessels[0].params.observe = Infinity; }, p => { p.vessels.pop(); }]) {
    const bad = structuredClone(project); mutate(bad); assert.throws(() => M.validateProject(bad), /phase|fraction|control|vessel/i);
  }
});

test("rendered material recipes retain base controls, effective controls and the model identity", async () => {
  const M = model(), project = await fixture(), parent = project.sources[0];
  const output = await M.createSource(new Uint8Array([4, 5, 6, 7]), {
    name: "Material output.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1 });
  output.recipe = { schema: "brahma.native-recipe.v1", parentId: parent.id, module: "ditto_morphic_core",
    params: { observe: .9, assume: .26, mutate: .25 }, baseParams: { observe: .5, assume: .5, mutate: .1 },
    material: { schema: "brahma.material-state.v1", modelVersion: 1, phase: "gas", amount: 1, composition: [{ id: "water", fraction: 1 }] },
    inputSha256: "c".repeat(64), definitionSha256: "a".repeat(64), rackSha256: "b".repeat(64), modelSha256: "d".repeat(64) };
  project.sources.push(output);
  const reopened = await M.deserialize(M.serialize(project));
  assert.deepEqual(reopened.sources[1].recipe, output.recipe);
  const bad = structuredClone(project); bad.sources[1].recipe.modelSha256 = "missing";
  assert.throws(() => M.validateProject(bad), /material|model|hash/i);
});

// ---- plan step 6 (#95): save/reopen against the new SC slice path ----

async function fixtureTwo() {
  const M = model(), project = await fixture();
  const second = await M.createSource(new Uint8Array([4, 5, 6, 7]), {
    name: "second.wav", mime: "audio/wav", duration: 4, sampleRate: 8000, channels: 1,
  });
  project.sources.push(second);
  project.trackSources[1] = second.id;
  P.setCell(project.scene, 1, 0, { note: 60, vel: 0.5, sampleId: second.id, slice: 1 });
  return { M, project, second };
}

test("slice tracks round-trip through save/reopen, with the SC transform fields", async () => {
  const { M, project } = await fixtureTwo();
  project.sliceTracks = [
    { slice: 2, sourceTempo: 120, rate: 1, transform: "timestretch", stretchRate: null, stretchPitch: 0.5, stretchGrain: 0.05 },
    { slice: 0, sourceTempo: null, rate: 0.5, transform: "none", stretchRate: null, stretchPitch: 1, stretchGrain: 0.1 },
    null, null, null,
  ];
  const reopened = await M.deserialize(M.serialize(project));
  assert.deepEqual(reopened.sliceTracks, project.sliceTracks);
  // Sessions saved before step 6 carry no sliceTracks and reopen unbound.
  assert.deepEqual(M.validateProject(await fixture()).sliceTracks, [null, null, null, null, null]);
});

test("slice tracks reject bindings the engine cannot play", async () => {
  const { M, project } = await fixtureTwo();
  project.sliceTracks = [
    { slice: 2, sourceTempo: 120, rate: 1, transform: "timestretch", stretchRate: null, stretchPitch: 0.5, stretchGrain: 0.05 },
    null, null, null, null,
  ];
  for (const mutate of [
    p => { p.sliceTracks[0].transform = "reverse"; },
    p => { p.sliceTracks[0].slice = 8; },
    p => { p.sliceTracks[2] = { slice: 0 }; },
    p => { p.sliceTracks[0].rate = 5; },
    p => { p.sliceTracks[0].stretchPitch = 0.1; },
    p => { p.sliceTracks[0].stretchGrain = 2; },
    p => { p.sliceTracks[0].sourceTempo = -3; },
    p => { p.sliceTracks.pop(); },
  ]) {
    const bad = structuredClone(project); mutate(bad);
    assert.throws(() => M.validateProject(bad), /slice|transform|rate|pitch|grain|tempo|track/i);
  }
});

test("sliceTrackMessages restores the SC sequencer state in order", async () => {
  const { M, project } = await fixtureTwo();
  project.sliceTracks = [
    { slice: 2, sourceTempo: 120, rate: 1, transform: "timestretch", stretchRate: null, stretchPitch: 0.5, stretchGrain: 0.05 },
    { slice: 0, sourceTempo: null, rate: 0.5, transform: "none", stretchRate: null, stretchPitch: 1, stretchGrain: 0.1 },
    null, null, null,
  ];
  assert.deepEqual(M.sliceTrackMessages(project), [
    { address: "/golem/slice/bind", args: [0, 2, 120] },
    { address: "/golem/slice/transform", args: [0, "timestretch"] },
    { address: "/golem/slice/stretch", args: [0, 0, 0.5, 0.05] },
    { address: "/golem/slice/bind", args: [1, 0, 0] },
    { address: "/golem/slice/rate", args: [1, 0.5] },
  ]);
  assert.deepEqual(M.sliceTrackMessages(await fixture()), []);
});

test("reopen reports a referenced-but-unembedded asset and restores the playable remainder", async () => {
  const { M, project, second } = await fixtureTwo();
  const referenced = M.createReference({
    name: "library song.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
    ref: { path: "donors/library song.wav", sha256: "e".repeat(64) },
  });
  project.sources.push(referenced);
  project.trackSources[2] = referenced.id;
  project.sliceTracks = [null, null, { slice: 1 }, null, null];
  P.setCell(project.scene, 2, 0, { note: 60, vel: 0.5, sampleId: referenced.id, slice: 1 });
  // Strict reopening keeps the reference named: its bytes are not in the
  // file, so there is nothing to verify and nothing to silently drop.
  const strict = await M.deserialize(M.serialize(project));
  assert.equal(strict.sources.length, 3);
  assert.equal(strict.sources[2].data, null);
  assert.deepEqual(strict.sources[2].ref, { path: "donors/library song.wav", sha256: "e".repeat(64) });
  // Tolerant reopening reports it missing and restores the playable rest.
  const { project: restored, report } = await M.reopen(M.serialize(project));
  assert.equal(restored.sources.length, 2);
  assert.equal(report.missing.length, 1);
  assert.equal(report.missing[0].reason, "referenced but not embedded");
  assert.equal(report.missing[0].ref, "donors/library song.wav");
  assert.equal(restored.scene.grid[2][0], null);
  assert.equal(restored.trackSources[2], null);
  assert.equal(restored.sliceTracks[2], null);
  assert.equal(report.droppedCells.length, 1);
  assert.deepEqual(report.droppedCells[0], { track: 2, step: 0, sampleId: referenced.id, slice: 1 });
  assert.equal(report.droppedSliceTracks.length, 1);
  assert.deepEqual(report.droppedSliceTracks[0], { track: 2, sampleId: referenced.id });
  // The surviving sources and their notes are untouched.
  assert.equal(restored.scene.grid[0][0].sampleId, project.sources[0].id);
  assert.equal(restored.scene.grid[1][0].sampleId, second.id);
});

test("reopen salvages a session with one corrupt source instead of losing it", async () => {
  const { M, project } = await fixtureTwo();
  project.sources[1].data = "AQIDBA=="; // valid base64, wrong bytes for second.wav's hash
  await assert.rejects(M.deserialize(JSON.stringify(project)), /integrity/i);
  const { project: restored, report } = await M.reopen(JSON.stringify(project));
  assert.equal(restored.sources.length, 1);
  assert.equal(restored.sources[0].id, project.sources[0].id);
  assert.equal(report.missing.length, 1);
  assert.equal(report.missing[0].reason, "source audio integrity check failed");
  assert.equal(restored.scene.grid[1][0], null);
  assert.equal(restored.trackSources[1], null);
  assert.equal(restored.scene.grid[0][0].sampleId, project.sources[0].id);
});

test("reopen drops a recipe child whose parent did not survive", async () => {
  const M = model(), project = await fixture(), parent = project.sources[0];
  const output = await M.createSource(new Uint8Array([4, 5, 6, 7]), {
    name: "Native pitch.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
  });
  output.recipe = { schema: "brahma.native-recipe.v1", parentId: parent.id, module: "solve_pitch_shift",
    params: { semitones: -7, mix: .75 }, inputSha256: "c".repeat(64),
    definitionSha256: "a".repeat(64), rackSha256: "b".repeat(64) };
  project.sources.push(output);
  project.sources[0].data = "AQIDBA=="; // corrupt the parent
  const { project: restored, report } = await M.reopen(JSON.stringify(project));
  assert.equal(restored.sources.length, 0);
  assert.equal(report.missing.length, 2);
  assert.ok(report.missing.some(m => m.reason === "source audio integrity check failed"));
  assert.ok(report.missing.some(m => m.reason === "recipe parent missing"));
});

test("replacing a track sound keeps an in-range slice binding and clears an out-of-range one", async () => {
  const { M, project, second } = await fixtureTwo();
  const narrow = await M.createSource(new Uint8Array([8, 9, 10, 11]), {
    name: "narrow.wav", mime: "audio/wav", duration: 4, sampleRate: 8000, channels: 1,
  });
  narrow.slices = narrow.slices.slice(0, 4);
  project.sources.push(narrow);
  project.sliceTracks = [
    { slice: 6, sourceTempo: null, rate: 1, transform: "none", stretchRate: null, stretchPitch: 1, stretchGrain: 0.1 },
    null, null, null, null,
  ];
  // In-range swap: track 0 to `second` (8 chops) keeps chop 6.
  const kept = M.replaceTrackSource(project, 0, project.sources[0].id, second.id);
  assert.equal(kept.sliceTracks[0].slice, 6);
  // Out-of-range swap: track 0 to `narrow` (4 chops) clears the binding.
  const cleared = M.replaceTrackSource(kept, 0, second.id, narrow.id);
  assert.equal(cleared.sliceTracks[0], null);
});

test("relative asset references cannot escape the library", () => {
  const M = model();
  const ok = M.createReference({ name: "song.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
    ref: { path: "donors/song.wav", sha256: "e".repeat(64) } });
  assert.equal(ok.ref.path, "donors/song.wav");
  assert.equal(ok.data, null);
  for (const path of ["/absolute/song.wav", "../escape.wav", "donors/../escape.wav", "donors\\song.wav", ""]) {
    assert.throws(() => M.createReference({ name: "song.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
      ref: { path, sha256: "e".repeat(64) } }), /asset reference/i);
  }
  assert.throws(() => M.createReference({ name: "song.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
    ref: { path: "donors/song.wav", sha256: "not-a-hash" } }), /asset reference/i);
});
