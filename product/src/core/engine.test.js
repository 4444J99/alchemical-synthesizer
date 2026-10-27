"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const dgram = require("node:dgram");
const { once } = require("node:events");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");

test("engine evidence and specimen simulation stay honest", { timeout: 10000 }, async (t) => {
  const data = fs.mkdtempSync(path.join(os.tmpdir(), "foundry-engine-"));
  const peer = dgram.createSocket("udp4");
  peer.bind(0, "127.0.0.1");
  await once(peer, "listening");
  process.env.FOUNDRY_DATA_DIR = data;
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

  await t.test("fresh engine evidence cannot turn a simulated specimen into rendered audio", async () => {
    await freshTelemetry();
    const dispatched = [];
    const capture = (packet) => dispatched.push(osc.readPacket(packet, { metadata: false, unpackSingleArgs: false }));
    peer.on("message", capture);
    try {
      const specimen = engine.renderSpecimen({ module: "Azoth" });
      assert.equal(specimen.simulated, true);
      assert.equal(specimen.audioUrl, null);
      assert.equal(store.collection("specimens").find((row) => row.id === specimen.id), specimen);
      await delay(30);
      assert.deepEqual(dispatched, [], "no renderer completion contract exists to dispatch");
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

  await t.test("closing the telemetry transport clears its evidence", async () => {
    await freshTelemetry();
    const closed = once(receiver, "close");
    receiver.close();
    await closed;
    assert.equal(engine.isOnline(), false);
    assert.deepEqual(engine.organismState(), []);
  });
});
