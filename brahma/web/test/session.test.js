"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { createTokenBucket } = require("../lib/ratelimit");
const { createLiveSessions, createSession, oscArgs, MAX_DUR_SECS } = require("../lib/session");

const HUMAN = "human-token-123456789012345678";
const AGENT = "agent-token-1234567890123456789";

/** Deterministic clock plus a fake socket. */
function harness({ role = null, ratePerSec = 1000, burst = 1000 } = {}) {
  let clock = 1000;
  const now = () => clock;
  const oscSent = [];
  const frames = [];
  const state = { role };

  const sessions = createLiveSessions({ now });
  const limiter = createTokenBucket({ ratePerSec, burst, now });

  const session = createSession({
    getRole: () => state.role,
    setRole: (r) => { state.role = r; },
    exchangeHuman: (t) => t === HUMAN,
    isAgentToken: (t) => t === AGENT,
    sendOsc: (address, args) => oscSent.push({ address, args }),
    allowedPrefixes: ["/brahma/", "/golem/"],
    limiter,
    sessions,
    send: (p) => frames.push(p)
  });

  return {
    session,
    sessions,
    state,
    oscSent,
    frames,
    advance: (ms) => { clock += ms; },
    last: () => frames[frames.length - 1],
    clear: () => { frames.length = 0; oscSent.length = 0; }
  };
}

function asHuman(h) {
  h.state.role = "human";
  return h;
}

// ---------------------------------------------------------------- ratelimit

test("ratelimit: bucket drains, refuses, then refills", () => {
  let t = 0;
  const b = createTokenBucket({ ratePerSec: 10, burst: 3, now: () => t });

  assert.equal(b.take(1).ok, true);
  assert.equal(b.take(1).ok, true);
  assert.equal(b.take(1).ok, true);

  const refused = b.take(1);
  assert.equal(refused.ok, false);
  assert.ok(refused.retryAfterMs > 0);

  t = 1000; // 1s at 10/s → 10 tokens, capped at burst
  assert.equal(b.take(1).ok, true);
  assert.equal(b.state().tokens < 3, true);
});

test("ratelimit: rejects nonsense configuration", () => {
  assert.throws(() => createTokenBucket({ ratePerSec: 0 }));
  assert.throws(() => createTokenBucket({ burst: 0 }));
});

// -------------------------------------------------------------------- auth

test("session: human token yields human role", () => {
  const h = harness();
  h.session.handle(JSON.stringify({ type: "auth", token: HUMAN })); // allow-secret
  assert.deepEqual(h.last(), { type: "auth", ok: true, role: "human" });
  assert.equal(h.state.role, "human");
});

test("session: agent token yields agent role, never human", () => {
  const h = harness();
  h.session.handle(JSON.stringify({ type: "auth", token: AGENT })); // allow-secret
  assert.equal(h.last().role, "agent");
  assert.equal(h.state.role, "agent");
});

test("session: bad token is rejected with a typed error", () => {
  const h = harness();
  h.session.handle(JSON.stringify({ type: "auth", token: "nope" })); // allow-secret
  assert.equal(h.last().type, "error");
  assert.equal(h.last().code, "invalid_token");
  assert.equal(h.state.role, null);
});

test("session: malformed frames produce typed errors, never throw", () => {
  const h = harness({ role: "human" });
  h.session.handle("not json");
  assert.equal(h.last().code, "bad_json");
  h.session.handle(JSON.stringify(["array"]));
  assert.equal(h.last().code, "bad_frame");
  h.session.handle(JSON.stringify({ type: "wat" }));
  assert.equal(h.last().code, "unknown_type");
});

// --------------------------------------------------------------------- run

test("session: run registers a pattern and pings the engine", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ type: "run", id: "p1", engine: "chimera", instance: "i1" }));

  const ack = h.last();
  assert.equal(ack.type, "ack");
  assert.equal(ack.action, "run");
  assert.equal(ack.id, "p1");
  assert.deepEqual(h.oscSent, [{ address: "/brahma/live/ping", args: [] }]);
  assert.equal(h.sessions.patterns.size, 1);
});

test("session: run rejects duplicate ids and bad ids", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ type: "run", id: "p1" }));
  h.session.handle(JSON.stringify({ type: "run", id: "p1" }));
  assert.equal(h.last().code, "duplicate_id");

  h.session.handle(JSON.stringify({ type: "run", id: "bad id with spaces" }));
  assert.equal(h.last().code, "bad_id");
});

test("session: agent cannot run", () => {
  const h = harness({ role: "agent" });
  h.session.handle(JSON.stringify({ type: "run", id: "p1" }));
  assert.equal(h.last().code, "forbidden");
  assert.equal(h.sessions.patterns.size, 0);
});

test("session: unauthenticated cannot run", () => {
  const h = harness();
  h.session.handle(JSON.stringify({ type: "run", id: "p1" }));
  assert.equal(h.last().code, "forbidden");
});

// ------------------------------------------------------------------- event

test("session: event maps to /brahma/live/play with clamped arguments", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({
    type: "event", id: "p1", engine: "chimera", instance: "i1",
    note: 60.7, vel: 1.9, dur: 999, params: ["cutoff", 800]
  }));

  assert.equal(h.oscSent.length, 1);
  const sent = h.oscSent[0];
  assert.equal(sent.address, "/brahma/live/play");
  assert.equal(sent.args[0], "chimera");
  assert.equal(sent.args[1], "i1");
  assert.equal(sent.args[2], 61, "note rounds to an integer");
  assert.equal(sent.args[3], 1, "velocity clamps to 1");
  assert.equal(sent.args[4], MAX_DUR_SECS, "duration clamps to the engine cap");
  assert.deepEqual(sent.args.slice(5), ["cutoff", 800]);
});

test("session: event rejects non-numeric note/vel/dur", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ type: "event", note: "loud", vel: 1, dur: 1 }));
  assert.equal(h.last().code, "bad_args");
  assert.equal(h.oscSent.length, 0);
});

test("session: event is rate limited without dropping the connection", () => {
  const h = asHuman(harness({ ratePerSec: 1, burst: 2 }));
  const one = JSON.stringify({ type: "event", note: 60, vel: 1, dur: 1 });

  h.session.handle(one);
  h.session.handle(one);
  h.session.handle(one);

  assert.equal(h.oscSent.length, 2, "burst of 2 forwards");
  assert.equal(h.last().code, "rate_limited");
  assert.ok(h.last().detail.retryAfterMs > 0);

  h.advance(5000); // refill
  h.session.handle(one);
  assert.equal(h.oscSent.length, 3, "connection remains usable after the burst");
});

// -------------------------------------------------------------- stop/panic

test("session: stop releases that instance's voices only", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ type: "run", id: "p1", instance: "i1" }));
  h.clear();

  h.session.handle(JSON.stringify({ type: "stop", id: "p1" }));
  assert.deepEqual(h.oscSent, [{ address: "/brahma/engine/freeAll", args: ["i1"] }]);
  assert.equal(h.sessions.patterns.size, 0);
});

test("session: stop of an unknown pattern is a typed error", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ type: "stop", id: "ghost" }));
  assert.equal(h.last().code, "unknown_pattern");
  assert.equal(h.oscSent.length, 0);
});

test("session: stop_all panics the engine and clears the registry", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ type: "run", id: "p1" }));
  h.session.handle(JSON.stringify({ type: "run", id: "p2" }));
  h.clear();

  h.session.handle(JSON.stringify({ type: "stop_all" }));
  assert.deepEqual(h.oscSent, [{ address: "/brahma/live/panic", args: [] }]);
  assert.equal(h.sessions.patterns.size, 0);
  assert.deepEqual(h.last().patterns.sort(), ["p1", "p2"]);
});

test("session: stop_all is human-only", () => {
  const h = harness({ role: "agent" });
  h.session.handle(JSON.stringify({ type: "stop_all" }));
  assert.equal(h.last().code, "forbidden");
  assert.equal(h.oscSent.length, 0);
});

// ------------------------------------------------------------------ status

test("session: status reports no_pong_yet before the engine answers", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ type: "status" }));
  const s = h.last();
  assert.equal(s.type, "status");
  assert.equal(s.engine.ok, false);
  assert.equal(s.engine.reason, "no_pong_yet");
});

test("session: status is fresh after a pong and stale after the window", () => {
  const h = asHuman(harness());
  h.sessions.recordPong(42, 3);
  h.session.handle(JSON.stringify({ type: "status" }));
  assert.equal(h.last().engine.ok, true);
  assert.equal(h.last().engine.modules, 42);

  h.advance(10000);
  h.session.handle(JSON.stringify({ type: "status" }));
  assert.equal(h.last().engine.ok, false);
  assert.equal(h.last().engine.reason, "stale");
});

test("session: agent may read status but not control", () => {
  const h = harness({ role: "agent" });
  h.session.handle(JSON.stringify({ type: "status" }));
  assert.equal(h.last().type, "status");
});

test("session: unauthenticated status is forbidden", () => {
  const h = harness();
  h.session.handle(JSON.stringify({ type: "status" }));
  assert.equal(h.last().code, "forbidden");
});

// ------------------------------------------------------------- legacy OSC

test("session: legacy OSC inside the allowlist still forwards for humans", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ address: "/brahma/engine/noteOn", args: ["chimera", "i1", 60, 0.8] }));
  assert.deepEqual(h.oscSent, [
    { address: "/brahma/engine/noteOn", args: ["chimera", "i1", 60, 0.8] }
  ]);
});

test("session: legacy OSC outside the allowlist is refused", () => {
  const h = asHuman(harness());
  h.session.handle(JSON.stringify({ address: "/dirt/play", args: [] }));
  assert.equal(h.last().code, "forbidden_address");
  assert.equal(h.oscSent.length, 0);
});

test("session: legacy OSC is human-only", () => {
  const h = harness({ role: "agent" });
  h.session.handle(JSON.stringify({ address: "/brahma/engine/noteOn", args: [] }));
  assert.equal(h.last().code, "forbidden");
});

test("session: legacy OSC is rate limited too", () => {
  const h = asHuman(harness({ ratePerSec: 1, burst: 1 }));
  const frame = JSON.stringify({ address: "/brahma/engine/noteOn", args: [] });
  h.session.handle(frame);
  h.session.handle(frame);
  assert.equal(h.oscSent.length, 1);
  assert.equal(h.last().code, "rate_limited");
});

// ----------------------------------------------------------------- helpers

test("oscArgs: types integers, floats and strings for metadata mode", () => {
  assert.deepEqual(oscArgs([60, 0.5, "x"]), [
    { type: "i", value: 60 },
    { type: "f", value: 0.5 },
    { type: "s", value: "x" }
  ]);
});
