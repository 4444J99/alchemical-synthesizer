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

test("Instrument Bridge — slice addressing (plan step 3)", async (t) => {
  await t.test("receiver accepts an explicit slice and keeps the pitch fallback", () => {
    const content = octa();
    assert.ok(
      content.includes("slice = if(msg.size > 5) { msg[5].asInteger } { nil };"),
      "Receiver must read the optional 5th arg as the explicit slice"
    );
    assert.ok(
      content.includes("sliceIndex = slice ? (note % (nodes[\\numSlices]"),
      "Explicit slice must win when present; absent slice falls back to note % numSlices"
    );
  });

  await t.test("out-of-range slice gets a typed ack and starts no voice", () => {
    const content = octa();
    // Scope to the instrument-note receiver: the /octahedron/slice responder
    // above it also triggers the slicer, so a file-wide indexOf would point
    // at the wrong trigger call. The receiver now sounds the note through
    // the shared ~octahedron_playSlice helper (plan step 4), not an inline
    // Synth call — the contract is unchanged: the range check must precede
    // the trigger.
    const receiver = content.slice(content.indexOf("OSCdef(\\instrument_note"));
    const rangeIdx = receiver.indexOf("bad_args: slice out of range");
    assert.ok(rangeIdx !== -1, "Out-of-range slice must get a typed ack, never a silent clip");
    const playIdx = receiver.indexOf("~octahedron_playSlice.(");
    assert.ok(playIdx !== -1 && rangeIdx < playIdx, "Range check must precede the slice trigger");
  });

  await t.test("the edited .scd stays bracket-balanced (a missing close breaks the CI compile)", () => {
    const content = octa();
    for (const [open, close] of [["{", "}"], ["(", ")"], ["[", "]"]]) {
      const opens = content.split(open).length - 1;
      const closes = content.split(close).length - 1;
      assert.equal(opens, closes, `25_elektron_octatrack.scd: ${opens} '${open}' vs ${closes} '${close}'`);
    }
  });

  await t.test("browser sends the cell's chop for sample events, four args otherwise", () => {
    const instrument = fs.readFileSync(INSTRUMENT_JS, "utf8");
    assert.ok(
      instrument.includes("if (ev.sampleId != null) args.push(ev.slice"),
      "OscAdapter must append the cell's slice for sample events"
    );
    assert.ok(
      !instrument.includes('throw new Error("Imported samples play in WebAudio'),
      "OSC must no longer refuse sample events — the engine can sound the exact chop now"
    );
    assert.ok(
      !instrument.includes('samples.report("Imported samples play in WebAudio'),
      "play() must no longer refuse the OSC engine when cells carry samples"
    );
  });

  await t.test("pattern.js carries the chop through expansion (behavioral)", () => {
    const Pattern = require("../public/instrument/pattern.js");
    const scene = Pattern.makeScene(16, 5);
    Pattern.setCell(scene, 0, 0, { note: 60, vel: 0.8, sampleId: "src-1", slice: 2 });
    const evs = Pattern.expandCell(scene.grid[0][0], 0.5, Pattern.makeRng(1));
    assert.equal(evs.length, 1, "Sample cell must expand to one event");
    assert.equal(evs[0].sampleId, "src-1", "Event must keep its sample identity");
    assert.equal(evs[0].slice, 2, "Event must carry the cell's chosen chop");
    // A plain note event carries no slice: the receiver derives it from pitch.
    const plain = Pattern.expandCell({ note: 60, vel: 0.8 }, 0.5);
    assert.equal(plain[0].slice, undefined, "Plain note must not carry a slice");
  });
});
