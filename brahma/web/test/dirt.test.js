"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const osc = require("osc");
const {
  parseDirtArgs,
  translateDirtMessage,
  createDirtBridge,
  DEFAULT_DIRT_PORT,
  DEFAULT_SC_PORT
} = require("../lib/dirt");

test("Dirt Bridge — parseDirtArgs", async (t) => {
  await t.test("parses flat alternating key-value array", () => {
    const raw = ["s", "azoth", "n", 60, "gain", 0.9, "delta", 0.25];
    const parsed = parseDirtArgs(raw);
    assert.deepEqual(parsed, {
      s: "azoth",
      n: 60,
      gain: 0.9,
      delta: 0.25
    });
  });

  await t.test("parses typed metadata object array", () => {
    const raw = [
      { type: "s", value: "s" }, { type: "s", value: "prima_materia" },
      { type: "s", value: "n" }, { type: "i", value: 67 },
      { type: "s", value: "gain" }, { type: "f", value: 0.75 }
    ];
    const parsed = parseDirtArgs(raw);
    assert.deepEqual(parsed, {
      s: "prima_materia",
      n: 67,
      gain: 0.75
    });
  });

  await t.test("handles object input directly", () => {
    const raw = { s: "buchlaeus", n: 48 };
    assert.deepEqual(parseDirtArgs(raw), { s: "buchlaeus", n: 48 });
  });

  await t.test("handles empty or odd-length arrays gracefully", () => {
    assert.deepEqual(parseDirtArgs([]), {});
    assert.deepEqual(parseDirtArgs(null), {});
    assert.deepEqual(parseDirtArgs(["s", "azoth", "orphanKey"]), { s: "azoth" });
  });
});

test("Dirt Bridge — translateDirtMessage", async (t) => {
  await t.test("translates /dirt/play to /brahma/live/play with defaults", () => {
    const msg = { address: "/dirt/play", args: [] };
    const res = translateDirtMessage(msg, { metadata: false });
    assert.ok(res);
    assert.equal(res.address, "/brahma/live/play");
    assert.equal(res.args[0], "prima_materia"); // default engine
    assert.equal(res.args[1], "dirt_prima_materia_0"); // default instance
    assert.equal(res.args[2], 60); // default note
    assert.equal(res.args[3], 0.8); // default vel
    assert.equal(res.args[4], 0.5); // default dur
  });

  await t.test("translates /play2 with full parameters and metadata format", () => {
    const msg = {
      address: "/play2",
      args: ["s", "azoth", "n", 72, "gain", 0.6, "delta", 1.5, "orbit", 2, "cutoff", 2500]
    };
    const res = translateDirtMessage(msg, { metadata: true });
    assert.ok(res);
    assert.equal(res.address, "/brahma/live/play");
    assert.equal(res.args[0].value, "azoth");
    assert.equal(res.args[1].value, "dirt_azoth_2");
    assert.equal(res.args[2].value, 72);
    assert.equal(res.args[2].type, "i");
    assert.equal(res.args[3].value, 0.6);
    assert.equal(res.args[3].type, "f");
    assert.equal(res.args[4].value, 1.5);
    assert.equal(res.args[4].type, "f");
    assert.equal(res.args[5].value, "cutoff");
    assert.equal(res.args[6].value, 2500);
  });

  await t.test("clamps note, gain, and duration to valid ranges", () => {
    const msg = {
      address: "/dirt/play",
      args: ["n", 200, "gain", 5.0, "delta", 50.0]
    };
    const res = translateDirtMessage(msg, { metadata: false });
    assert.equal(res.args[2], 127); // clamped to 127
    assert.equal(res.args[3], 1.0); // clamped to 1.0
    assert.equal(res.args[4], 30.0); // clamped to maxVoiceSecs 30
  });

  await t.test("filters reserved keys from extra synthesis parameters", () => {
    const msg = {
      address: "/dirt/play",
      args: ["s", "logos", "n", 60, "cps", 0.5, "cycle", 12, "resonance", 1.8]
    };
    const res = translateDirtMessage(msg, { metadata: false });
    const extra = res.args.slice(5);
    assert.deepEqual(extra, ["resonance", 1.8]);
  });

  await t.test("translates /dirt/panic to /brahma/live/panic", () => {
    const res = translateDirtMessage({ address: "/dirt/panic", args: [] });
    assert.ok(res);
    assert.equal(res.address, "/brahma/live/panic");
    assert.deepEqual(res.args, []);
  });

  await t.test("rejects unsupported addresses", () => {
    assert.equal(translateDirtMessage({ address: "/unknown/cmd", args: [] }), null);
    assert.equal(translateDirtMessage(null), null);
  });
});

test("Dirt Bridge — UDP Network Round-Trip", async () => {
  const TEST_DIRT_PORT = 58130;
  const TEST_SC_PORT = 58120;

  // 1. Setup mock SuperCollider UDP listener
  const mockSc = new osc.UDPPort({
    localAddress: "127.0.0.1",
    localPort: TEST_SC_PORT,
    metadata: true
  });

  await new Promise((resolve) => {
    mockSc.on("ready", resolve);
    mockSc.open();
  });

  // 2. Setup Dirt Bridge
  const bridge = createDirtBridge({
    port: TEST_DIRT_PORT,
    scPort: TEST_SC_PORT,
    scHost: "127.0.0.1",
    bindAddress: "127.0.0.1",
    metadata: true
  });

  await new Promise((resolve) => {
    bridge.on("ready", resolve);
    bridge.start();
  });

  // 3. Send test /dirt/play UDP packet from Tidal mock client
  const client = new osc.UDPPort({
    localAddress: "127.0.0.1",
    localPort: 0,
    remoteAddress: "127.0.0.1",
    remotePort: TEST_DIRT_PORT,
    metadata: true
  });

  await new Promise((resolve) => {
    client.on("ready", resolve);
    client.open();
  });

  const receivedPromise = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Timeout waiting for SC message")), 2000);
    mockSc.on("message", (msg) => {
      clearTimeout(timer);
      resolve(msg);
    });
  });

  client.send({
    address: "/dirt/play",
    args: [
      { type: "s", value: "s" }, { type: "s", value: "chrysopoeia" },
      { type: "s", value: "n" }, { type: "i", value: 64 },
      { type: "s", value: "gain" }, { type: "f", value: 0.85 },
      { type: "s", value: "delta" }, { type: "f", value: 0.75 }
    ]
  });

  const scMsg = await receivedPromise;
  assert.equal(scMsg.address, "/brahma/live/play");
  assert.equal(scMsg.args[0].value, "chrysopoeia");
  assert.equal(scMsg.args[1].value, "dirt_chrysopoeia_0");
  assert.equal(scMsg.args[2].value, 64);
  assert.ok(Math.abs(scMsg.args[3].value - 0.85) < 0.001);
  assert.ok(Math.abs(scMsg.args[4].value - 0.75) < 0.001);

  // Clean teardown
  client.close();
  bridge.close();
  mockSc.close();
});
