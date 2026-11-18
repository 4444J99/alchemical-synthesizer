"use strict";

// Instrument bridge — song sampling (#95, plan steps 1-2).
//
// The browser instrument sends /brahma/instrument/note for every pattern
// event when the OSC engine is selected, and the slicer needs a real buffer
// bound to sliceBuf before it can sound. These are static contract tests
// in the live_bridge.test.js style: sclang is not available in this VM,
// and CI's native-dsp job compile-checks every .scd under brahma/sc
// (tools/dsp/compile.scd), so these tests pin the contract the compiled
// code must keep — receiver, acks, read-only load, release-before-replace,
// and stop — rather than re-parsing SuperCollider.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const OCTATRACK_SCD = path.resolve(__dirname, "../../sc/25_elektron_octatrack.scd");
const GATEWAY_SCD = path.resolve(__dirname, "../../sc/31_live_gateway.scd");
const INSTRUMENT_JS = path.resolve(__dirname, "../public/instrument/instrument.js");

function octa() {
  return fs.readFileSync(OCTATRACK_SCD, "utf8");
}

test("Instrument Bridge — /brahma/instrument/note receiver exists", async (t) => {
  await t.test("25_elektron_octatrack.scd defines the instrument-note receiver", () => {
    const content = octa();
    assert.ok(content.includes("OSCdef(\\instrument_note"), "Must define OSCdef(\\instrument_note)");
    assert.ok(content.includes('"/brahma/instrument/note"'), "Receiver must listen on /brahma/instrument/note");
  });

  await t.test("receiver maps note to slice and triggers the slicer with gain", () => {
    const content = octa();
    assert.ok(content.includes("note % (nodes[\\numSlices]"), "Note must select sliceIndex via note % numSlices");
    assert.ok(content.includes("Synth(\\octahedron_slicer"), "Receiver must trigger the octahedron slicer");
    assert.ok(content.includes("\\amp, gain,"), "Receiver must pass the browser gain as slicer amp");
    assert.ok(content.includes("\\bufnum, buf,"), "Receiver must play the bound sliceBuf, not bufnum 0");
  });

  await t.test("receiver auto-releases after dur, like /brahma/live/play", () => {
    const content = octa();
    assert.ok(content.includes("dur.wait;"), "Auto-release must wait for dur");
    assert.ok(
      content.includes("~octahedron_sliceReleaseVoice.(nodes, syn);"),
      "Auto-release must release only the voice it started"
    );
  });

  await t.test("receiver acknowledges every outcome — an open socket is not an ack", () => {
    const content = octa();
    assert.ok(content.includes("/brahma/instrument/note/ack"), "Must reply on /brahma/instrument/note/ack");
    assert.ok(content.includes("no buffer loaded"), "No-buffer case must say so, not stay silent");
    assert.ok(content.includes("bad_args: note out of range"), "Out-of-range note must get a typed ack");
  });

  await t.test("browser and engine agree on the note contract", () => {
    const instrument = fs.readFileSync(INSTRUMENT_JS, "utf8");
    assert.ok(
      instrument.includes('address: "/brahma/instrument/note"'),
      "instrument.js must send /brahma/instrument/note"
    );
    assert.ok(
      instrument.includes("P.TRACKS[track], ev.note"),
      "instrument.js must send [track, note, gain, dur]"
    );
    assert.ok(octa().includes('"/brahma/instrument/note"'), "SC side must listen on the same address");
  });
});

test("Instrument Bridge — /octahedron/load binds a real buffer", async (t) => {
  await t.test("25_elektron_octatrack.scd defines the load responder", () => {
    const content = octa();
    assert.ok(content.includes("OSCdef(\\octahedron_load"), "Must define OSCdef(\\octahedron_load)");
    assert.ok(content.includes('"/octahedron/load"'), "Load responder must listen on /octahedron/load");
    assert.ok(content.includes("Buffer.read(s, path"), "Load must read the source with Buffer.read");
  });

  await t.test("load validates the path before any server call", () => {
    const content = octa();
    assert.ok(content.includes("File.exists(path)"), "Load must reject a missing file synchronously");
    assert.ok(content.includes("SoundFile.openRead(path)"), "Load must reject an unreadable audio file");
    assert.ok(content.includes("/octahedron/load/state"), "Load must reply on /octahedron/load/state");
  });

  await t.test("load never writes the source file", () => {
    const content = octa();
    assert.ok(!content.includes("Buffer.write"), "Load path must never Buffer.write");
    assert.ok(!content.includes("SoundFile.write"), "Load path must never SoundFile.write");
    assert.ok(!content.includes("File.write"), "Load path must never File.write");
  });

  await t.test("replacement releases voices before binding, and frees the old buffer after", () => {
    const content = octa();
    const stopIdx = content.indexOf("oldVoices = ~octahedron_sliceStopAll.(nodes);");
    const bindIdx = content.indexOf("nodes[\\sliceBuf] = buf;");
    assert.ok(stopIdx !== -1, "Load must gate off sounding slice voices on replace");
    assert.ok(bindIdx !== -1, "Load must bind the new buffer to sliceBuf");
    assert.ok(stopIdx < bindIdx, "Voices must stop BEFORE the new buffer binds");
    assert.ok(content.includes("0.1.wait; oldBuf.free;"), "Old buffer must free after the release tail");
  });

  await t.test("a later load supersedes an in-flight one (loadToken guard)", () => {
    const content = octa();
    assert.ok(content.includes("loadToken: 0"), "Node holder must init loadToken");
    assert.ok(content.includes("token == nodes[\\loadToken]"), "Load action must bind only if still current");
  });

  await t.test("numSlices is bounded and stored on load", () => {
    const content = octa();
    assert.ok(content.includes("msg[2].asInteger.clip(1, 128)"), "numSlices arg must clip to 1..128");
    assert.ok(content.includes("nodes[\\numSlices] = slices"), "Load must store the requested slice count");
  });
});

test("Instrument Bridge — stop releases voices", async (t) => {
  await t.test("25_elektron_octatrack.scd defines the stop responder", () => {
    const content = octa();
    assert.ok(content.includes("OSCdef(\\octahedron_stop"), "Must define OSCdef(\\octahedron_stop)");
    assert.ok(content.includes('"/octahedron/stop"'), "Stop responder must listen on /octahedron/stop");
    assert.ok(content.includes("/octahedron/stop/state"), "Stop must reply with the freed count");
    assert.ok(content.includes("sliceVoices: List.new"), "Node holder must track slice voices");
  });

  await t.test("/octahedron/slice tracks its voice so stop can release it", () => {
    const content = octa();
    assert.ok(content.includes("nodes[\\sliceVoices].add(syn);"), "Slice trigger must track its voice");
  });

  await t.test("live panic stops slice voices too", () => {
    const gateway = fs.readFileSync(GATEWAY_SCD, "utf8");
    assert.ok(gateway.includes('"/octahedron/stop"'), "Panic path list must include /octahedron/stop");
  });
});

test("Instrument Bridge — slicer gain control", () => {
  const content = octa();
  assert.ok(content.includes("amp=1.0"), "Slicer SynthDef must accept an amp argument");
  assert.ok(content.includes("play * env * amp"), "Slicer output must scale by amp");
  assert.ok(content.includes("(\\name: \\amp,"), "Slicer registry entry must expose amp");
});
