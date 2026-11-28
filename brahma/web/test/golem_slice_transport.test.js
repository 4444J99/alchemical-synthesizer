"use strict";

// Golem shared transport — song sampling (#95, plan step 4).
//
// Slice tracks wire the Octatrack slicer into the live Golem sequencer:
// a bound track sounds its chop on the shared project transport, with
// the chop's native length preserved separately from project tempo.
// Static contract tests in the instrument_bridge.test.js style: sclang
// is not available in this VM, and CI's native-dsp job compile-checks
// every .scd under brahma/sc (tools/dsp/compile.scd), so these tests
// pin the contract the compiled code must keep — slice-track fields,
// the shared voice path, native chop timing, the OSC surface, honest
// rate labelling, and scene persistence — rather than re-parsing
// SuperCollider.

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

test("Golem Slice Transport — slice-track fields", async (t) => {
  await t.test("every track carries slice-track state, off by default", () => {
    const content = sequencer();
    assert.ok(content.includes("sliceTrack: false,"), "Tracks must default sliceTrack to false");
    assert.ok(content.includes("sliceIndex: 0,"), "Tracks must default sliceIndex to 0");
    assert.ok(content.includes("sourceTempo: nil,"), "Tracks must default sourceTempo to nil (unknown)");
    assert.ok(content.includes("rate: 1.0,"), "Tracks must default playback rate to 1.0");
  });

  await t.test("source tempo is stored, never imposed on the voice", () => {
    const content = sequencer();
    // The bind handler stores sourceTempo and reports it; nothing in the
    // slice path retunes the project clock or the chop to match it.
    const bind = content.slice(content.indexOf("OSCdef(\\golem_slice_bind"));
    assert.ok(bind.includes("track[\\sourceTempo] = if(tempo > 0) { tempo } { nil };"),
      "Bind must store the clip's native BPM, or nil when unknown");
    assert.ok(!bind.includes("setTempo"), "Bind must never retune the project clock");
  });
});

test("Golem Slice Transport — shared voice path", async (t) => {
  await t.test("25_ defines one slice voice helper for receiver and sequencer", () => {
    const content = octa();
    assert.ok(
      content.includes("~octahedron_playSlice = { |nodes, sliceIndex, rate, gain, dur, outBus|"),
      "Must define ~octahedron_playSlice(nodes, sliceIndex, rate, gain, dur, outBus)"
    );
    assert.ok(content.includes("Synth(\\octahedron_slicer"), "Helper must trigger the octahedron slicer");
    assert.ok(content.includes("\\amp, gain,"), "Helper must pass gain as the slicer amp");
    assert.ok(content.includes("\\bufnum, buf,"), "Helper must play the bound sliceBuf, not bufnum 0");
    assert.ok(content.includes("\\rate, rate.clip(-4, 4),"), "Helper must clip playback rate to -4..4");
    assert.ok(content.includes("if(buf.isNil) { nil }"), "Helper must return nil with no buffer bound");
  });

  await t.test("helper auto-releases after dur, like /brahma/live/play", () => {
    const content = octa();
    assert.ok(content.includes("dur.wait;"), "Helper must wait for dur before releasing");
    assert.ok(
      content.includes("~octahedron_sliceReleaseVoice.(nodes, syn);"),
      "Helper must release only the voice it started"
    );
  });

  await t.test("the instrument-note receiver sounds through the helper", () => {
    const content = octa();
    assert.ok(
      content.includes("~octahedron_playSlice.(nodes, sliceIndex, 1.0, gain, dur, nodes[\\mainBus] ? 0);"),
      "Receiver must call the helper with rate 1.0 and the main bus"
    );
  });

  await t.test("the sequencer trigger sounds through the helper on the track bus", () => {
    const content = sequencer();
    assert.ok(
      content.includes("~octahedron_playSlice.(~octahedron_nodes, slice, track[\\rate], vel, sliceDur, track[\\audioBus].index);"),
      "Sequencer must call the helper with the track rate, step velocity, native chop length, and track bus"
    );
  });
});

test("Golem Slice Transport — one transport, source timing", async (t) => {
  await t.test("the trigger branches on sliceTrack inside the step loop", () => {
    const content = sequencer();
    const loop = content.slice(content.indexOf("Tdef(\\golem_seq"));
    assert.ok(loop.includes("if(track[\\sliceTrack])"), "Step loop must branch on sliceTrack");
    assert.ok(
      loop.includes("step[\\pLocks][\\slice]"),
      "A per-step p-lock named slice must override the track's chop"
    );
  });

  await t.test("the slice gate is the chop's native length, not the project step", () => {
    const content = sequencer();
    assert.ok(content.includes("sliceDuration: { |self, track|"), "Must define sliceDuration");
    const dur = content.slice(content.indexOf("sliceDuration: { |self, track|"));
    assert.ok(dur.includes("buf.numFrames"), "Native length must come from the buffer's frames");
    assert.ok(dur.includes("buf.sampleRate"), "Native length must divide by the buffer's sample rate");
    assert.ok(dur.includes("track[\\rate].abs.max(0.01)"), "Native length must divide by |rate|");
    assert.ok(!dur.includes("stepDur"), "Native length must never use the project step duration");
  });

  await t.test("no buffer, or slicer not loaded, means no voice", () => {
    const content = sequencer();
    const dur = content.slice(content.indexOf("sliceDuration: { |self, track|"));
    assert.ok(dur.includes("if(nodes.isNil or: { ~octahedron_playSlice.isNil }) { ^nil };"),
      "sliceDuration must return nil when the slicer is not loaded");
    assert.ok(dur.includes("if(buf.isNil) { ^nil };"),
      "sliceDuration must return nil when no buffer is bound");
  });

  await t.test("a step with no buffer, or an out-of-range chop, warns and starts no voice", () => {
    const content = sequencer();
    const branch = content.slice(content.indexOf("if(track[\\sliceTrack])"));
    const noBufIdx = branch.indexOf("has no buffer loaded");
    const rangeIdx = branch.indexOf("out of range (0..%)");
    const playIdx = branch.indexOf("~octahedron_playSlice.(~octahedron_nodes");
    assert.ok(noBufIdx !== -1, "Missing buffer must warn, not stay silent");
    assert.ok(rangeIdx !== -1, "Out-of-range chop must warn, never a silent clip");
    assert.ok(playIdx !== -1 && noBufIdx < playIdx && rangeIdx < playIdx,
      "Both guards must precede the slice trigger");
  });

  await t.test("pitch humanization does not apply to slice tracks", () => {
    const content = sequencer();
    const loop = content.slice(content.indexOf("Tdef(\\golem_seq"));
    assert.ok(
      loop.includes("Pitch humanization does not"),
      "The slice branch must state that pitch humanization does not apply"
    );
    // pitchOff is computed only on the drum path, after the slice branch.
    assert.ok(
      loop.indexOf("if(track[\\sliceTrack])") < loop.indexOf("pitchOff = rrand"),
      "pitchOff must be computed after the slice branch, on the drum path only"
    );
  });
});

test("Golem Slice Transport — OSC surface", async (t) => {
  await t.test("bind, rate, and unbind responders exist", () => {
    const content = sequencer();
    assert.ok(content.includes("OSCdef(\\golem_slice_bind"), "Must define OSCdef(\\golem_slice_bind)");
    assert.ok(content.includes('"/golem/slice/bind"'), "Bind must listen on /golem/slice/bind");
    assert.ok(content.includes("OSCdef(\\golem_slice_rate"), "Must define OSCdef(\\golem_slice_rate)");
    assert.ok(content.includes('"/golem/slice/rate"'), "Rate must listen on /golem/slice/rate");
    assert.ok(content.includes("OSCdef(\\golem_slice_unbind"), "Must define OSCdef(\\golem_slice_unbind)");
    assert.ok(content.includes('"/golem/slice/unbind"'), "Unbind must listen on /golem/slice/unbind");
  });

  await t.test("all three reply on one state address, and triggers broadcast", () => {
    const content = sequencer();
    assert.ok(content.includes('"/golem/slice/state"'), "Must reply on /golem/slice/state");
    assert.ok(content.includes('"/golem/slice/trigger"'), "Must broadcast /golem/slice/trigger");
    assert.ok(content.includes('"/golem/track/trigger"'), "Slice steps must still broadcast /golem/track/trigger");
  });

  await t.test("rate is playback rate only, never independent pitch/time stretch", () => {
    const content = sequencer();
    assert.ok(content.includes("playback rate only"), "Rate must be labelled playback rate only");
    assert.ok(content.includes("octahedron_timestretch"),
      "The slice section must name the timestretch voice as the owner of independent pitch/time");
    const rate = content.slice(content.indexOf("OSCdef(\\golem_slice_rate"));
    assert.ok(rate.includes("msg[2].asFloat.clip(-4, 4)"), "Rate must clip to -4..4 like the slicer");
    assert.ok(rate.includes("rate only, not pitch/time stretch"),
      "The rate handler must state its own limit: rate only, not pitch/time stretch");
  });

  await t.test("out-of-range track indices warn instead of throwing", () => {
    const content = sequencer();
    assert.ok(content.includes("Slice bind: track % out of range"), "Bind must guard the track index");
    assert.ok(content.includes("Slice rate: track % out of range"), "Rate must guard the track index");
    assert.ok(content.includes("Slice unbind: track % out of range"), "Unbind must guard the track index");
  });
});

test("Golem Slice Transport — scenes and evict", async (t) => {
  await t.test("scenes save and restore slice bindings", () => {
    const content = sequencer();
    assert.ok(content.includes("sliceTrack: t[\\sliceTrack],"), "saveScene must persist sliceTrack");
    assert.ok(content.includes("sliceIndex: t[\\sliceIndex],"), "saveScene must persist sliceIndex");
    assert.ok(content.includes("sourceTempo: t[\\sourceTempo],"), "saveScene must persist sourceTempo");
    assert.ok(content.includes("rate: t[\\rate]"), "saveScene must persist rate");
    assert.ok(content.includes("data[\\sliceTrack] ? false"), "loadScene must default sliceTrack for old scenes");
    assert.ok(content.includes("data[\\sliceIndex] ? 0"), "loadScene must default sliceIndex for old scenes");
    assert.ok(content.includes("data[\\rate] ? 1.0"), "loadScene must default rate for old scenes");
  });

  await t.test("evict clears slice bindings with the factory reset", () => {
    const content = golem();
    const evict = content.slice(content.indexOf("evict: { |self|"));
    assert.ok(evict.includes("track[\\sliceTrack] = false;"), "Evict must clear sliceTrack");
    assert.ok(evict.includes("track[\\sliceIndex] = 0;"), "Evict must clear sliceIndex");
    assert.ok(evict.includes("track[\\sourceTempo] = nil;"), "Evict must clear sourceTempo");
    assert.ok(evict.includes("track[\\rate] = 1.0;"), "Evict must reset rate");
  });
});

test("Golem Slice Transport — edited .scd files stay bracket-balanced", () => {
  assertBalanced(sequencer(), "15_golem_sequencer.scd");
  assertBalanced(golem(), "15_golem.scd");
  assertBalanced(octa(), "25_elektron_octatrack.scd");
});
