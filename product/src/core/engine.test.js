"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const dgram = require("node:dgram");
const { once } = require("node:events");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");

/** Poll a check with real-time delays (Date.now is mocked in this file). */
async function waitFor(check, label) {
  for (let i = 0; i < 100; i++) {
    if (check()) return;
    await delay(5);
  }
  assert.fail(`timed out waiting for ${label}`);
}

/** Write a minimal PCM WAV fixture and return its measured properties. */
function writeWavFixture(file, { channels = 2, sampleRate = 44100, bitsPerSample = 16, frames = 44100 } = {}) {
  const bytesPerSample = bitsPerSample / 8;
  const blockAlign = channels * bytesPerSample;
  const dataSize = frames * blockAlign;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(36 + dataSize, 4);
  header.write("WAVE", 8, "ascii");
  header.write("fmt ", 12, "ascii");
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * blockAlign, 28); // byteRate
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(bitsPerSample, 34);
  header.write("data", 36, "ascii");
  header.writeUInt32LE(dataSize, 40);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.concat([header, Buffer.alloc(dataSize)]));
  return { channels, sampleRate, bitsPerSample, frames, durationSec: frames / sampleRate };
}

test("engine evidence and specimen simulation stay honest", { timeout: 10000 }, async (t) => {
  const data = fs.mkdtempSync(path.join(os.tmpdir(), "foundry-engine-"));
  const peer = dgram.createSocket("udp4");
  peer.bind(0, "127.0.0.1");
  await once(peer, "listening");
  process.env.FOUNDRY_DATA_DIR = data;
  process.env.FOUNDRY_RENDER_TIMEOUT_MS = "60"; // pending renders fail fast here; production default is 30000
  process.env.SC_HOST = "127.0.0.1";
  process.env.OSC_RECV_PORT = "0";
  process.env.OSC_SEND_PORT = String(peer.address().port);

  // Observe real sockets only to await binding and close resources after the
  // test. OSC encoding, UDP delivery, parsing, and the engine all remain real.
  const sockets = [];
  const createSocket = dgram.createSocket;
  const socketObserver = t.mock.method(dgram, "createSocket", (...args) => {
    const socket = createSocket(...args);
    const bind = socket.bind;
    // Confine the production bridge's wildcard bind to loopback in this test.
    socket.bind = (port, _address, callback) => bind.call(socket, port, "127.0.0.1", callback);
    sockets.push(socket);
    return socket;
  });
  const engine = require("./engine");
  const store = require("./store");
  const osc = require("osc");
  let now = 10000;
  t.mock.method(Date, "now", () => now);
  t.after(async () => {
    await Promise.all([...sockets, peer].map((socket) => new Promise((resolve) => {
      try { socket.close(resolve); } catch { resolve(); }
    })));
    store.flushSync();
    fs.rmSync(data, { recursive: true, force: true });
  });
  engine.start();
  socketObserver.mock.restore();
  await Promise.all(sockets.map((socket) => once(socket, "listening")));
  const receiver = sockets[0];
  const sendTelemetry = async (args, address = "/brahma/organism/update") => {
    const received = once(receiver, "message");
    peer.send(Buffer.from(osc.writePacket({ address, args })), receiver.address().port, "127.0.0.1");
    await received;
  };
  const freshTelemetry = async () => {
    now += 3000;
    engine.organismState();
    await sendTelemetry([1001, "Proteus", 0.5, 1.25]);
  };

  await t.test("a bound local UDP listener is not evidence of an engine", () => {
    assert.equal(engine.isOnline(), false);
    assert.equal(engine.send("/brahma/test", []), false);
  });

  await t.test("malformed telemetry cannot establish availability or populate organisms", async () => {
    const malformed = [
      [], [1001, "Proteus"], ["", "Proteus", 0.5, 1],
      [1001, "", 0.5, 1], [1001, "Proteus", "0.5", 1],
      [1001, "Proteus", NaN, 1], [1001, "Proteus", Infinity, 1],
      [1001, "Proteus", -0.1, 1], [1001, "Proteus", 1.1, 1],
      [1001, "Proteus", 0.5, -1]
    ];
    for (const args of malformed) {
      now += 3000;
      engine.organismState();
      await sendTelemetry(args);
      assert.equal(engine.isOnline(), false, JSON.stringify(args));
      assert.deepEqual(engine.organismState(), []);
    }
  });

  await t.test("validated observed telemetry enables command dispatch", async () => {
    await freshTelemetry();
    assert.equal(engine.isOnline(), true);
    assert.deepEqual(engine.organismState(), [
      { id: 1001, type: "Proteus", coherence: 0.5, entropy: 1.25, lastUpdate: now }
    ]);
    const received = once(peer, "message");
    assert.equal(engine.send("/brahma/test", [7]), true);
    const [packet] = await received;
    assert.deepEqual(osc.readPacket(packet, { metadata: false, unpackSingleArgs: false }), { address: "/brahma/test", args: [7] });
  });

  await t.test("stale evidence expires even when unrelated or invalid packets arrive", async () => {
    await freshTelemetry();
    now += 1999;
    await sendTelemetry(["ignored"], "/unrelated");
    await sendTelemetry([1001, "Proteus", "invalid", 1]);
    now += 2;
    assert.equal(engine.isOnline(), false);
    assert.deepEqual(engine.organismState(), []);
    assert.equal(engine.send("/brahma/test", []), false);
  });

  await t.test("fresh engine evidence dispatches a render that stays pending without a completion receipt", async () => {
    await freshTelemetry();
    const dispatched = [];
    const capture = (packet) => dispatched.push(osc.readPacket(packet, { metadata: false, unpackSingleArgs: false }));
    peer.on("message", capture);
    try {
      const specimen = engine.renderSpecimen({ module: "Azoth" });
      // Dispatch happened, but nothing about the render is claimed yet: the
      // specimen is still simulated, with no audio, until a completion
      // receipt is verified against a measured file.
      assert.equal(specimen.simulated, true);
      assert.equal(specimen.audioUrl, null);
      assert.equal(specimen.renderState, "pending");
      assert.equal(specimen.renderId, specimen.id);
      assert.equal(store.collection("specimens").find((row) => row.id === specimen.id), specimen);
      await delay(30);
      assert.equal(dispatched.length, 1);
      assert.equal(dispatched[0].address, "/brahma/foundry/render");
      assert.equal(dispatched[0].args[0], specimen.id);
      assert.equal(dispatched[0].args[1], "Azoth");
      assert.equal(dispatched[0].args[2], 4);
      assert.equal(typeof dispatched[0].args[3], "string");
      assert.ok(dispatched[0].args[3].endsWith(`${specimen.id}.wav`));
    } finally { peer.off("message", capture); }
  });

  await t.test("specimen ownership comes only from trusted invocation context", () => {
    const unowned = engine.renderSpecimen({ module: "Azoth", ownerEmail: "spoof@example.test" });
    assert.equal(unowned.ownerEmail, null);
    const owned = engine.renderSpecimen(
      { module: "Azoth", ownerEmail: "spoof@example.test", creator: "display handle" },
      { ownerEmail: "owner@example.test" }
    );
    assert.equal(owned.ownerEmail, "owner@example.test");
    assert.equal(owned.creator, "display handle");
  });

  // ---- issue #96: the five required render-lifecycle cases ----

  await t.test("(a) absent peer: no telemetry, no dispatch, specimen stays simulated", async () => {
    now += 3000;
    engine.organismState(); // expire any telemetry left by earlier tests
    assert.equal(engine.isOnline(), false);
    const dispatched = [];
    const capture = (packet) => dispatched.push(osc.readPacket(packet, { metadata: false, unpackSingleArgs: false }));
    peer.on("message", capture);
    try {
      const specimen = engine.renderSpecimen({ module: "Azoth" });
      assert.equal(specimen.simulated, true);
      assert.equal(specimen.audioUrl, null);
      assert.equal(specimen.renderState, "unavailable");
      assert.equal(specimen.renderId, specimen.id);
      await delay(30);
      assert.deepEqual(dispatched, []);
    } finally { peer.off("message", capture); }
  });

  await t.test("(b) stale peer: dispatch refused once telemetry expires, pending render fails closed", async () => {
    await freshTelemetry();
    const specimen = engine.renderSpecimen({ module: "Azoth" });
    assert.equal(specimen.renderState, "pending");
    now += 3000;
    engine.organismState(); // telemetry is stale now: the pending render must fail closed
    const row = store.collection("specimens").find((s) => s.id === specimen.id);
    assert.equal(row.renderState, "failed");
    assert.equal(row.audioUrl, null);
    assert.equal(row.simulated, true);
    // A new render while stale is refused outright.
    const dispatched = [];
    const capture = (packet) => dispatched.push(osc.readPacket(packet, { metadata: false, unpackSingleArgs: false }));
    peer.on("message", capture);
    try {
      const refused = engine.renderSpecimen({ module: "Azoth" });
      assert.equal(refused.renderState, "unavailable");
      await delay(30);
      assert.deepEqual(dispatched, []);
    } finally { peer.off("message", capture); }
  });

  await t.test("(c) dispatch with no completion: pending, then timeout fails it closed; late receipts ignored", async () => {
    await freshTelemetry();
    const specimen = engine.renderSpecimen({ module: "Azoth" });
    assert.equal(specimen.renderState, "pending");
    await waitFor(
      () => store.collection("specimens").find((s) => s.id === specimen.id).renderState === "failed",
      "pending render to time out");
    const row = store.collection("specimens").find((s) => s.id === specimen.id);
    assert.equal(row.audioUrl, null);
    assert.equal(row.simulated, true);
    // A completion receipt arriving after the timeout must not resurrect it.
    await sendTelemetry([specimen.renderId, "ok", "/tmp/never-arrived.wav"], "/brahma/foundry/render/done");
    await delay(20);
    assert.equal(store.collection("specimens").find((s) => s.id === specimen.id).renderState, "failed");
    assert.equal(store.collection("specimens").find((s) => s.id === specimen.id).audioUrl, null);
  });

  await t.test("(d) failed rendering: engine /failed receipt fails the render closed", async () => {
    await freshTelemetry();
    const specimen = engine.renderSpecimen({ module: "Azoth" });
    assert.equal(specimen.renderState, "pending");
    await sendTelemetry([specimen.renderId, "nrt exit 1"], "/brahma/foundry/render/failed");
    await waitFor(
      () => store.collection("specimens").find((s) => s.id === specimen.id).renderState === "failed",
      "failed receipt to settle");
    const row = store.collection("specimens").find((s) => s.id === specimen.id);
    assert.equal(row.audioUrl, null);
    assert.equal(row.simulated, true);
  });

  await t.test("(e) valid measured file completion: receipt + real file completes the render", async () => {
    await freshTelemetry();
    const specimen = engine.renderSpecimen({ module: "Azoth" });
    assert.equal(specimen.renderState, "pending");
    const expected = path.join(store.DATA_DIR, "specimens", `${specimen.renderId}.wav`);
    const measured = writeWavFixture(expected, { channels: 2, sampleRate: 44100, frames: 44100 });
    // The echoed path is deliberately bogus: completion trusts the file the
    // engine locates itself under FOUNDRY_DATA_DIR, never the peer's claim.
    await sendTelemetry([specimen.renderId, "ok", "/tmp/evil.wav"], "/brahma/foundry/render/done");
    await waitFor(
      () => store.collection("specimens").find((s) => s.id === specimen.id).renderState === "complete",
      "completion receipt to settle");
    const row = store.collection("specimens").find((s) => s.id === specimen.id);
    assert.equal(row.simulated, false);
    assert.equal(row.audioUrl, `${specimen.renderId}.wav`);
    assert.equal(row.durationSec, measured.durationSec);
    assert.equal(row.renderState, "complete");
    assert.ok(row.renderCompletedAt);
    // The file the completion measured is the one under FOUNDRY_DATA_DIR.
    assert.ok(fs.existsSync(expected));
  });

  await t.test("closing the telemetry transport clears its evidence", async () => {
    await freshTelemetry();
    const closed = once(receiver, "close");
    receiver.close();
    await closed;
    assert.equal(engine.isOnline(), false);
    assert.deepEqual(engine.organismState(), []);
  });
});
