"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const P = require("../public/instrument/pattern.js");
const M = require("../public/instrument/sample-project.js");
const A = require("../public/instrument/sample-audio.js");

// A synthetic stereo fixture: a 440 Hz sine, opposite polarity per channel
// so the two channels are provably distinct, with no audio device involved.
function stereoFixture({ seconds = 1, rate = 44100, amplitude = 0.5, hz = 440 } = {}) {
  const frames = Math.round(seconds * rate);
  const left = new Float32Array(frames), right = new Float32Array(frames);
  for (let i = 0; i < frames; i++) {
    const value = amplitude * Math.sin(2 * Math.PI * hz * i / rate);
    left[i] = value; right[i] = -value;
  }
  return { numberOfChannels: 2, length: frames, sampleRate: rate,
    getChannelData: channel => channel === 0 ? left : right };
}
function silenceFixture() {
  const frames = 4410;
  const data = new Float32Array(frames);
  return { numberOfChannels: 2, length: frames, sampleRate: 44100,
    getChannelData: () => data };
}
async function fixtureProject() {
  const source = await M.createSource(new Uint8Array([0, 1, 2, 3]), {
    name: "donor.wav", mime: "audio/wav", duration: 8, sampleRate: 8000, channels: 1,
  });
  const scene = P.makeScene(16, 5);
  P.setCell(scene, 0, 0, { note: 60, vel: 0.8, sampleId: source.id, slice: 2 });
  return { schema: "brahma.sample-project.v1", name: "Export session", tempo: 104,
    phase: "manual", cycle: 3, scene, trackSources: [source.id, null, null, null, null],
    sliceTracks: [{ slice: 2, sourceTempo: 120, rate: 1, transform: "none",
      stretchRate: null, stretchPitch: 1, stretchGrain: 0.1 }, null, null, null, null],
    sources: [source] };
}
function sha256(bytes) {
  return crypto.createHash("sha256").update(Buffer.from(bytes)).digest("hex");
}

test("wavBytes encodes the synthetic stereo fixture as valid 16-bit stereo RIFF", () => {
  const rendered = stereoFixture();
  const bytes = Buffer.from(A.wavBytes(rendered));
  assert.equal(bytes.toString("ascii", 0, 4), "RIFF");
  assert.equal(bytes.toString("ascii", 8, 12), "WAVE");
  assert.equal(bytes.readUInt16LE(20), 1, "PCM format");
  assert.equal(bytes.readUInt16LE(22), 2, "stereo");
  assert.equal(bytes.readUInt32LE(24), 44100);
  assert.equal(bytes.readUInt16LE(34), 16);
  assert.equal(bytes.readUInt32LE(40), 44100 * 2 * 2, "exactly one second of stereo frames");
  // Opposite polarity per channel: the first nonzero frame is + on the left
  // channel and - on the right, so the fixture is provably stereo, not dual mono.
  let frame = 0;
  while (rendered.getChannelData(0)[frame] === 0) frame++;
  assert.ok(bytes.readInt16LE(44 + frame * 4) > 0);
  assert.ok(bytes.readInt16LE(44 + frame * 4 + 2) < 0);
});

test("measureAudio reads the fixture's level and gates silence as not audible", () => {
  const measured = A.measureAudio(stereoFixture());
  assert.equal(measured.sampleRate, 44100);
  assert.equal(measured.channels, 2);
  assert.equal(measured.frames, 44100);
  assert.equal(measured.durationSeconds, 1);
  assert.ok(Math.abs(measured.rms - 0.5 / Math.SQRT2) < 0.001, `rms ${measured.rms}`);
  assert.ok(Math.abs(measured.peak - 0.5) < 0.001, `peak ${measured.peak}`);
  assert.equal(measured.audible, true);
  const silent = A.measureAudio(silenceFixture());
  assert.equal(silent.rms, 0);
  assert.equal(silent.peak, 0);
  assert.equal(silent.audible, false);
  assert.throws(() => A.measureAudio({ numberOfChannels: 0, length: 0, sampleRate: 44100, getChannelData: () => new Float32Array(0) }), /audio buffer/i);
});

test("exportReceipt ties the WAV to the exact session bytes and its render", async () => {
  const project = await fixtureProject();
  const sessionText = M.serialize(project);
  const sessionSha256 = await M.digest(new TextEncoder().encode(sessionText));
  const rendered = stereoFixture();
  const wav = A.wavBytes(rendered);
  const measurements = A.measureAudio(rendered);
  const exportedAt = new Date("2026-11-18T22:15:53.123Z");
  const receipt = A.exportReceipt({ project, sessionSha256,
    wavSha256: sha256(wav), wavByteLength: wav.byteLength,
    wavFilename: "Export-session-loop-take1-20261118T221553123Z.wav",
    receiptFilename: "Export-session-loop-take1-20261118T221553123Z.receipt.json",
    measurements, take: 1, exportedAt });
  assert.equal(receipt.schema, "brahma.export-receipt.v1");
  assert.equal(receipt.take, 1);
  assert.equal(receipt.exportedAt, "2026-11-18T22:15:53.123Z");
  // The session tie: re-hashing the serialized session reproduces it.
  assert.equal(receipt.session.sha256, sessionSha256);
  assert.equal(receipt.session.schema, "brahma.sample-project.v1");
  assert.equal(receipt.session.name, "Export session");
  assert.equal(receipt.session.tempo, 104);
  assert.equal(receipt.session.cycle, 3);
  assert.equal(receipt.session.sources.length, 1);
  assert.equal(receipt.session.sources[0].sha256, project.sources[0].sha256);
  assert.deepEqual(receipt.session.sources[0].slices[2], { start: 2, end: 3 });
  assert.equal(receipt.session.sources[0].ref, null);
  assert.equal(receipt.session.sliceTracks[0].slice, 2);
  assert.equal(receipt.session.sliceTracks[0].sourceTempo, 120);
  // The WAV tie: re-hashing the bytes reproduces it.
  assert.equal(receipt.wav.sha256, sha256(wav));
  assert.equal(receipt.wav.byteLength, wav.byteLength);
  assert.equal(receipt.wav.filename, "Export-session-loop-take1-20261118T221553123Z.wav");
  assert.deepEqual(receipt.render, measurements);
  assert.equal(receipt.render.audible, true);
  assert.equal(receipt.receipt.filename, "Export-session-loop-take1-20261118T221553123Z.receipt.json");
});

test("exportReceipt rejects a session hash or project that does not verify", async () => {
  const project = await fixtureProject();
  const rendered = stereoFixture();
  const base = { project, sessionSha256: "0".repeat(64), wavSha256: sha256(A.wavBytes(rendered)),
    wavByteLength: 44 + 44100 * 4, wavFilename: "x.wav", receiptFilename: "x.receipt.json",
    measurements: A.measureAudio(rendered), take: 1, exportedAt: new Date() };
  assert.throws(() => A.exportReceipt({ ...base, sessionSha256: "not-a-hash" }), /session hash/i);
  assert.throws(() => A.exportReceipt({ ...base, wavSha256: "not-a-hash" }), /WAV hash/i);
  assert.throws(() => A.exportReceipt({ ...base, project: { schema: "nope" } }), /project format/i);
  assert.throws(() => A.exportReceipt({ ...base, measurements: { ...base.measurements, audible: "yes" } }), /measurements/i);
});

test("exportStem never reuses a basename across takes or moments", () => {
  const first = new Date("2026-11-18T22:15:53.123Z");
  const second = new Date("2026-11-18T22:15:53.124Z");
  assert.equal(A.exportStem("Export-session", 1, first), "Export-session-loop-take1-20261118T221553123Z");
  assert.notEqual(A.exportStem("Export-session", 2, first), A.exportStem("Export-session", 1, first));
  assert.notEqual(A.exportStem("Export-session", 1, second), A.exportStem("Export-session", 1, first));
  assert.notEqual(A.exportStem("Other-session", 1, first), A.exportStem("Export-session", 1, first));
  assert.match(A.exportStem("Export-session", 1, first), /^[A-Za-z0-9_-]+$/);
  assert.throws(() => A.exportStem("Export-session", 0, first), /take/i);
  assert.throws(() => A.exportStem("Export/session", 1, first), /export name/i);
  assert.throws(() => A.exportStem("Export session", 1, first), /export name/i);
  assert.throws(() => A.exportStem("Export-session", 1, new Date("invalid")), /export time/i);
});
