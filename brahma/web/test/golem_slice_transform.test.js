"use strict";

// Golem slice transformation — song sampling (#95, plan step 5).
//
// A slice track with transform \timestretch routes its chop through the
// existing granular time-stretch voice (\octahedron_timestretch) instead
// of the plain slicer: the pointer scans the chop at the tempo-match
// rate (project tempo / source tempo) while the grains play at an
// independent pitch, so a chop plays in project time with its pitch
// preserved. Static contract tests in the golem_slice_transport.test.js
// style: sclang is not available in this VM, and CI's native-dsp job
// compile-checks every .scd under brahma/sc (tools/dsp/compile.scd), so
// these tests pin the contract the compiled code must keep —
// transform fields, the stretched voice path, tempo-match resolution,
// the OSC surface, honest rate/pitch labelling, and scene persistence
// — rather than re-parsing SuperCollider.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const SEQUENCER_SCD = path.resolve(__dirname, "../../sc/15_golem_sequencer.scd");
const GOLEM_SCD = path.resolve(__dirname, "../../sc/15_golem.scd");
const OCTATRACK_SCD = path.resolve(__dirname, "../../sc/25_elektron_octatrack.scd");

function sequencer() {
  return fs.readFileSync(SEQUENCER_SCD, "utf8");
}

function golem() {
  return fs.readFileSync(GOLEM_SCD, "utf8");
}

function octa() {
  return fs.readFileSync(OCTATRACK_SCD, "utf8");
}

function assertBalanced(content, file) {
  for (const [open, close] of [["{", "}"], ["(", ")"], ["[", "]"]]) {
    const opens = content.split(open).length - 1;
    const closes = content.split(close).length - 1;
    assert.equal(opens, closes, `${file}: ${opens} '${open}' vs ${closes} '${close}'`);
  }
}

test("Golem Slice Transform — transform fields", async (t) => {
  await t.test("every track carries transform state, direct path by default", () => {
    const content = sequencer();
    assert.ok(content.includes("transform: \\none,"), "Tracks must default transform to \\none");
    assert.ok(content.includes("stretchRate: nil,"), "Tracks must default stretchRate to nil (auto tempo-match)");
    assert.ok(content.includes("stretchPitch: 1.0,"), "Tracks must default stretchPitch to 1.0 (own pitch)");
    assert.ok(content.includes("stretchGrain: 0.1,"), "Tracks must default stretchGrain to 0.1");
  });

  await t.test("the factory comment states what rate and pitch each mean", () => {
    const content = sequencer();
    assert.ok(content.includes("pointer scans the chop at the tempo-match rate"),
      "The transform comment must say rate is pointer speed, not pitch");
    assert.ok(content.includes("grains play at stretchPitch"),
      "The transform comment must say pitch is independent grain pitch");
  });
});

test("Golem Slice Transform — the stretched voice", async (t) => {
  await t.test("25_ bounds the timestretch voice to one chop and gates it", () => {
    const content = octa();
    const def = content.slice(content.indexOf("SynthDef(\\octahedron_timestretch"));
    assert.ok(def.includes("sliceIndex=0, numSlices=1, gate=1, amp=1.0"),
      "The timestretch voice must take slice bounds, a gate, and an amp");
    assert.ok(def.includes("sliceStart = sliceIndex.clip(0, numSlices.clip(1, 128) - 1) / numSlices.clip(1, 128);"),
      "The pointer must start at the chop's first frame");
    assert.ok(def.includes("start: sliceStart,"),
      "The Phasor must start at the slice start, not 0");
    assert.ok(def.includes("end: sliceEnd"),
      "The Phasor must end at the slice end, not 1");
    assert.ok(def.includes("Env.asr(0.001, 1, 0.005)"),
      "The voice must gate through the same ASR shape as the slicer");
    assert.ok(def.includes("doneAction: 2"),
      "The voice must free itself when gated off");
    assert.ok(def.includes("Out.ar(outBus, grains * env * amp);"),
      "The voice must sound through the gate envelope at the caller's gain");
  });

  await t.test("a bare timestretch voice still plays the whole buffer", () => {
    const content = octa();
    const def = content.slice(content.indexOf("SynthDef(\\octahedron_timestretch"));
    // numSlices defaults to 1, so sliceStart 0 / sliceEnd 1: the old
    // whole-buffer behaviour for the persistent /octahedron/stretch voice.
    assert.ok(def.includes("numSlices=1"), "numSlices must default to 1 (whole buffer)");
    assert.ok(def.includes("numSlices 1 is the whole buffer"),
      "The voice must document that the default is the old behaviour");
  });

  await t.test("GrainBuf rate is pitch, independent of the pointer speed", () => {
    const content = octa();
    const def = content.slice(content.indexOf("SynthDef(\\octahedron_timestretch"));
    assert.ok(def.includes("rate: pitch.clip(0.25, 4.0),"),
      "GrainBuf rate must be the pitch control, clipped 0.25..4");
    assert.ok(def.includes("rate: rate.clip(0.01, 4.0) * BufRateScale.kr(bufnum)"),
      "The pointer speed must be the rate control, clipped 0.01..4");
  });

  await t.test("25_ defines one stretched slice voice helper, mirroring playSlice", () => {
    const content = octa();
    assert.ok(
      content.includes("~octahedron_playSliceStretched = { |nodes, sliceIndex, rate, pitch, grainSize, gain, dur, outBus|"),
      "Must define ~octahedron_playSliceStretched(nodes, sliceIndex, rate, pitch, grainSize, gain, dur, outBus)"
    );
    const helper = content.slice(content.indexOf("~octahedron_playSliceStretched"));
    assert.ok(helper.includes("Synth(\\octahedron_timestretch"), "Helper must trigger the timestretch voice");
    assert.ok(helper.includes("\\sliceIndex, sliceIndex,"), "Helper must pass the chop");
    assert.ok(helper.includes("\\numSlices, nodes[\\numSlices] ? 16,"), "Helper must pass the slice count");
    assert.ok(helper.includes("\\rate, rate.clip(0.01, 4),"), "Helper must clip pointer speed to 0.01..4");
    assert.ok(helper.includes("\\pitch, pitch.clip(0.25, 4),"), "Helper must clip pitch to 0.25..4");
    assert.ok(helper.includes("\\grainSize, grainSize.clip(0.01, 1),"), "Helper must clip grain size to 0.01..1");
    assert.ok(helper.includes("\\amp, gain,"), "Helper must pass gain as the voice amp");
    assert.ok(helper.includes("if(buf.isNil) { nil }"), "Helper must return nil with no buffer bound");
    assert.ok(helper.includes("nodes[\\sliceVoices].add(syn);"),
      "Helper must track the voice so /octahedron/stop releases it");
    assert.ok(helper.includes("~octahedron_sliceReleaseVoice.(nodes, syn);"),
      "Helper must auto-release only the voice it started");
  });
});

test("Golem Slice Transform — tempo-match resolution", async (t) => {
  await t.test("sliceStretchRate resolves explicit, tempo-match, then track rate", () => {
    const content = sequencer();
    assert.ok(content.includes("sliceStretchRate: { |self, track|"), "Must define sliceStretchRate");
    const fn = content.slice(content.indexOf("sliceStretchRate: { |self, track|"));
    assert.ok(fn.includes("if(track[\\stretchRate].notNil)"),
      "An explicit stretchRate must win over tempo-match");
    assert.ok(fn.includes("rate = self.tempo / track[\\sourceTempo];"),
      "With a known source tempo, the rate must be project tempo / source tempo");
    assert.ok(fn.includes("rate = track[\\rate];"),
      "With no source tempo, the rate must fall back to the track rate");
    assert.ok(fn.includes("^rate.clip(0.01, 4);"), "The resolved rate must clip to the voice range");
  });

  await t.test("the step loop branches on transform inside the slice branch", () => {
    const content = sequencer();
    const loop = content.slice(content.indexOf("Tdef(\\golem_seq"));
    assert.ok(loop.includes("if(track[\\transform] == \\timestretch)"),
      "The step loop must branch on transform for slice tracks");
    assert.ok(
      loop.includes("~octahedron_playSliceStretched.(~octahedron_nodes, slice, stretchRate, track[\\stretchPitch], track[\\stretchGrain], vel, stretchDur, track[\\audioBus].index);"),
      "A stretched step must call the stretched helper with the resolved rate, pitch, grain, velocity, stretched length, and track bus"
    );
    assert.ok(
      loop.includes("stretchDur = sliceDur * track[\\rate].abs.max(0.01) / stretchRate.abs.max(0.01);"),
      "The stretched gate must be the native length divided by the pointer speed"
    );
  });

  await t.test("the stretched step stays behind the no-buffer and range guards", () => {
    const content = sequencer();
    const branch = content.slice(content.indexOf("if(track[\\sliceTrack])"));
    const noBufIdx = branch.indexOf("has no buffer loaded");
    const rangeIdx = branch.indexOf("out of range (0..%)");
    const stretchIdx = branch.indexOf("~octahedron_playSliceStretched.(~octahedron_nodes");
    assert.ok(stretchIdx !== -1, "The stretched trigger must exist in the slice branch");
    assert.ok(noBufIdx !== -1 && noBufIdx < stretchIdx, "The no-buffer guard must precede the stretched trigger");
    assert.ok(rangeIdx !== -1 && rangeIdx < stretchIdx, "The range guard must precede the stretched trigger");
  });
});

test("Golem Slice Transform — OSC surface", async (t) => {
  await t.test("transform and stretch responders exist", () => {
    const content = sequencer();
    assert.ok(content.includes("OSCdef(\\golem_slice_transform"), "Must define OSCdef(\\golem_slice_transform)");
    assert.ok(content.includes('"/golem/slice/transform"'), "Transform must listen on /golem/slice/transform");
    assert.ok(content.includes("OSCdef(\\golem_slice_stretch"), "Must define OSCdef(\\golem_slice_stretch)");
    assert.ok(content.includes('"/golem/slice/stretch"'), "Stretch must listen on /golem/slice/stretch");
  });

  await t.test("an unknown transform is rejected, never stored", () => {
    const content = sequencer();
    const handler = content.slice(content.indexOf("OSCdef(\\golem_slice_transform"));
    assert.ok(handler.includes("(name != \\none) and: { name != \\timestretch }"),
      "The handler must accept only \\none and \\timestretch");
    assert.ok(handler.includes("unknown transform % (none, timestretch)"),
      "An unknown transform must warn with the accepted names");
    assert.ok(handler.indexOf("unknown transform") < handler.indexOf("track[\\transform] = name;"),
      "The warn must precede any store, so a rejected name never lands");
  });

  await t.test("stretch stores nil for auto rate and clips pitch and grain", () => {
    const content = sequencer();
    const handler = content.slice(content.indexOf("OSCdef(\\golem_slice_stretch"));
    assert.ok(handler.includes("track[\\stretchRate] = if(rate.notNil and: { rate > 0 }) { rate.clip(0.01, 4) } { nil };"),
      "Rate 0 or omitted must store nil (auto tempo-match), a positive rate must clip to 0.01..4");
    assert.ok(handler.includes("track[\\stretchPitch] = pitch.clip(0.25, 4)"),
      "Pitch must clip to 0.25..4");
    assert.ok(handler.includes("track[\\stretchGrain] = grain.clip(0.01, 1)"),
      "Grain size must clip to 0.01..1");
  });

  await t.test("all five responders reply on one state address with the transform fields", () => {
    const content = sequencer();
    assert.ok(content.includes('"/golem/slice/state"'), "Must reply on /golem/slice/state");
    const stateSends = content.split('"/golem/slice/state"').length - 1;
    assert.equal(stateSends, 5, "Bind, rate, transform, stretch, and unbind must each reply on the one state address");
    assert.ok(content.includes("track[\\transform], track[\\stretchRate] ? 0, track[\\stretchPitch], track[\\stretchGrain]);"),
      "State replies must append transform, stretchRate, stretchPitch, stretchGrain after the step-4 args");
  });

  await t.test("out-of-range track indices warn instead of throwing", () => {
    const content = sequencer();
    assert.ok(content.includes("Slice transform: track % out of range"), "Transform must guard the track index");
    assert.ok(content.includes("Slice stretch: track % out of range"), "Stretch must guard the track index");
  });
});

test("Golem Slice Transform — scenes and evict", async (t) => {
  await t.test("scenes save and restore the transform fields", () => {
    const content = sequencer();
    assert.ok(content.includes("transform: t[\\transform],"), "saveScene must persist transform");
    assert.ok(content.includes("stretchRate: t[\\stretchRate],"), "saveScene must persist stretchRate");
    assert.ok(content.includes("stretchPitch: t[\\stretchPitch],"), "saveScene must persist stretchPitch");
    assert.ok(content.includes("stretchGrain: t[\\stretchGrain]"), "saveScene must persist stretchGrain");
    assert.ok(content.includes("data[\\transform] ? \\none"), "loadScene must default transform for old scenes");
    assert.ok(content.includes("data[\\stretchPitch] ? 1.0"), "loadScene must default stretchPitch for old scenes");
    assert.ok(content.includes("data[\\stretchGrain] ? 0.1"), "loadScene must default stretchGrain for old scenes");
  });

  await t.test("evict and unbind reset the transform fields with the chop", () => {
    const evict = golem().slice(golem().indexOf("evict: { |self|"));
    assert.ok(evict.includes("track[\\transform] = \\none;"), "Evict must reset transform");
    assert.ok(evict.includes("track[\\stretchRate] = nil;"), "Evict must reset stretchRate");
    assert.ok(evict.includes("track[\\stretchPitch] = 1.0;"), "Evict must reset stretchPitch");
    assert.ok(evict.includes("track[\\stretchGrain] = 0.1;"), "Evict must reset stretchGrain");
    const unbind = sequencer().slice(sequencer().indexOf("OSCdef(\\golem_slice_unbind"));
    assert.ok(unbind.includes("track[\\transform] = \\none;"), "Unbind must reset transform");
    assert.ok(unbind.includes("track[\\stretchRate] = nil;"), "Unbind must reset stretchRate");
  });

  await t.test("the direct path is untouched: the plain slicer still sounds", () => {
    const content = sequencer();
    assert.ok(
      content.includes("~octahedron_playSlice.(~octahedron_nodes, slice, track[\\rate], vel, sliceDur, track[\\audioBus].index);"),
      "A \\none track must still sound through the plain slicer at the track rate"
    );
  });
});

test("Golem Slice Transform — edited .scd files stay bracket-balanced", () => {
  assertBalanced(sequencer(), "15_golem_sequencer.scd");
  assertBalanced(golem(), "15_golem.scd");
  assertBalanced(octa(), "25_elektron_octatrack.scd");
});
