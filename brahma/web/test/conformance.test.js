"use strict";

/**
 * conformance.test.js — wire formats and runtime honesty.
 *
 * Two claims are under test, both of which are easy to fake and therefore worth a
 * test that fails loudly:
 *
 *   1. The Dirt bridge decodes the bytes SuperDirt actually receives. The fixtures
 *      are real OSC packets (see test/fixtures/dirt-wire.json for provenance): the
 *      test reads bytes, not JS objects, so an assumption about the `osc` library's
 *      metadata shape cannot hide here.
 *
 *   2. A runtime that is not installed says so. Tidal and Sonic Pi must report
 *      `not_installed` and the sclang gate must be closed unless it is explicitly
 *      opened — a green status for an unavailable engine is a lie the UI would repeat.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const osc = require("osc");

process.env.PORT = "0";
process.env.HOST = "127.0.0.1";
process.env.BRAHMA_OSC_LISTEN_PORT = "0";
process.env.BRAHMA_OSC_SEND_PORT = "57996";
process.env.BRAHMA_DIRT_PORT = "57136";
process.env.BRAHMA_HUMAN_TOKEN = "test-human-token-conformance-0001"; // allow-secret

const { server, closeServer } = require("../server");
const { translateDirtMessage } = require("../lib/dirt");

const FIXTURES = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures/dirt-wire.json"), "utf8")
).packets;

test.after(async () => {
  await new Promise((resolve) => closeServer(resolve));
});

const decode = (name) => osc.readPacket(Buffer.from(FIXTURES[name], "hex"), { metadata: true });

function url(p) {
  return `http://127.0.0.1:${server.address().port}${p}`;
}

function humanHeaders() {
  return {
    "content-type": "application/json",
    origin: `http://127.0.0.1:${server.address().port}`,
    cookie: `brahma_human=${process.env.BRAHMA_HUMAN_TOKEN}`
  };
}

/**
 * The sandbox self-test runs at boot and reports `uninitialized` until it finishes.
 * That is the honest answer, but a test that reads it too early is measuring its own
 * impatience, not the product — so wait for the probe to settle before asserting.
 */
async function waitForSandbox(timeoutMs = 20000) {
  const started = Date.now();
  for (;;) {
    const body = await fetch(url("/api/runtimes"), { headers: humanHeaders() }).then((r) => r.json());
    if (body.sandbox.reason !== "uninitialized") return body;
    if (Date.now() - started > timeoutMs) throw new Error("sandbox self-test never settled");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}

// ----------------------------------------------------------- Dirt wire conformance

test("Dirt conformance: a captured /dirt/play packet decodes to the documented fields", () => {
  const packet = decode("play");

  assert.equal(packet.address, "/dirt/play");
  const keys = packet.args.filter((_, i) => i % 2 === 0).map((a) => a.value);
  assert.deepEqual(keys, ["s", "n", "gain", "orbit", "cps", "delta"]);

  const translated = translateDirtMessage(packet);

  assert.equal(translated.address, "/brahma/live/play");
  assert.deepEqual(translated.args.map((a) => a.type), ["s", "s", "i", "f", "f"]);

  assert.equal(translated.args[0].value, "bd", "engine comes from `s`");
  assert.equal(translated.args[1].value, "dirt_bd_1", "instance is derived from engine and orbit");
  assert.equal(translated.args[2].value, 0, "`n` is the note");
  assert.equal(translated.args[3].value, 0.9, "`gain` is velocity");
  assert.equal(translated.args[4].value, 0.25, "`delta` is duration");
});

test("Dirt conformance: /dirt/panic forwards as the engine's panic address", () => {
  const translated = translateDirtMessage(decode("panic"));
  assert.equal(translated.address, "/brahma/live/panic");
  assert.deepEqual(translated.args, []);
});

test("Dirt conformance: /play2 aliases (sound, midinote, velocity) are honoured", () => {
  const translated = translateDirtMessage(decode("play2"));

  assert.equal(translated.address, "/brahma/live/play");
  assert.equal(translated.args[0].value, "sawtooth");
  assert.equal(translated.args[2].value, 64, "`midinote` wins over `n`");
  assert.equal(translated.args[3].value, 0.75, "`velocity` is accepted as gain");
});

test("Dirt conformance: every fixture packet is well-formed (no truncated hex)", () => {
  // A hand-copied hex string silently loses a character and breaks alignment, which
  // decodes into plausible-looking garbage. This is the check that catches that.
  for (const [name, hex] of Object.entries(FIXTURES)) {
    assert.match(hex, /^(?:[0-9a-f]{2})+$/, `${name}: hex must be whole bytes`);
    const packet = decode(name);
    assert.ok(packet.address.startsWith("/"), `${name}: address must be an OSC path`);
    for (const arg of packet.args) {
      if (arg.type === "s") {
        assert.ok(arg.value.length > 0, `${name}: empty string argument — fixture is misaligned`);
        assert.match(arg.value, /^[\x20-\x7e]+$/, `${name}: non-printable string — fixture is misaligned`);
      }
      if (arg.type === "d" || arg.type === "f") {
        assert.ok(Math.abs(arg.value) < 1e6, `${name}: absurd numeric ${arg.value} — fixture is misaligned`);
      }
    }
  }
});

test("Dirt conformance: an unsupported address is ignored, not guessed at", () => {
  const decoded = osc.readPacket(
    Buffer.from(osc.writePacket({ address: "/dirt/cps", args: [{ type: "d", value: 1 }] })),
    { metadata: true }
  );
  assert.equal(translateDirtMessage(decoded), null);
});

// ------------------------------------------------------------- runtime availability

test("runtimes: unavailable engines are reported as not_installed, never green", async () => {
  const body = await waitForSandbox();

  // /api/runtimes serves a map keyed by runtime id.
  assert.equal(typeof body.runtimes, "object");
  assert.ok(body.runtimes.tidalcycles, `must name tidalcycles (got ${Object.keys(body.runtimes).join(", ")})`);
  assert.ok(body.runtimes.sonicpi, "must name sonicpi");

  for (const id of ["tidalcycles", "sonicpi"]) {
    const rt = body.runtimes[id];
    if (rt.available) {
      assert.equal(rt.reason, "installed", `${id} available must report installed`);
    } else {
      assert.equal(rt.reason, "not_installed", `${id} unavailable must report not_installed`);
    }
  }

  // sclang is the one runtime that may be available here. Either answer is fine, but
  // it must be justified: available with no reason, or unavailable with a known one.
  const sclang = body.runtimes.sclang;
  assert.ok(sclang, "/api/runtimes must name sclang");
  if (sclang.available) {
    assert.ok(!sclang.reason, "an available runtime carries no failure reason");
  } else {
    assert.ok(
      ["not_installed", "sandbox_unavailable", "human_role_required", "disabled_by_env"].includes(sclang.reason),
      `unexpected sclang reason: ${sclang.reason}`
    );
  }
});

// ---------------------------------------------------------------- sclang opt-in gate

test("sclang gate: anonymous callers are refused before anything else", async () => {
  const res = await fetch(url("/api/runtimes/sclang/eval"), {
    method: "POST",
    headers: { "content-type": "application/json", origin: `http://127.0.0.1:${server.address().port}` },
    body: JSON.stringify({ code: "1+1" })
  });
  assert.equal(res.status, 403);
  assert.equal((await res.json()).error, "human_role_required");
});

test("sclang gate: the human role alone is not enough without the opt-in env var", async () => {
  const previous = process.env.BRAHMA_ALLOW_SCLANG;
  delete process.env.BRAHMA_ALLOW_SCLANG;

  try {
    const res = await fetch(url("/api/runtimes/sclang/eval"), {
      method: "POST",
      headers: humanHeaders(),
      body: JSON.stringify({ code: "1+1" })
    });
    assert.equal(res.status, 403);
    assert.equal((await res.json()).error, "sclang_disabled_by_env");
  } finally {
    if (previous !== undefined) process.env.BRAHMA_ALLOW_SCLANG = previous;
  }
});

test("sclang gate: with the opt-in set, request validation runs (the gate really opened)", async () => {
  const previous = process.env.BRAHMA_ALLOW_SCLANG;
  process.env.BRAHMA_ALLOW_SCLANG = "1";

  try {
    const res = await fetch(url("/api/runtimes/sclang/eval"), {
      method: "POST",
      headers: humanHeaders(),
      body: JSON.stringify({})
    });
    // Past the role gate and past the env gate: a missing body is now a 400, or a 503
    // if the sandbox self-test failed on this host. It must not still be a 403.
    assert.ok([400, 503].includes(res.status), `expected 400/503 past the gate, got ${res.status}`);
    assert.notEqual((await res.json()).error, "sclang_disabled_by_env");
  } finally {
    if (previous === undefined) delete process.env.BRAHMA_ALLOW_SCLANG;
    else process.env.BRAHMA_ALLOW_SCLANG = previous;
  }
});

test("sclang gate: the outcome matches the probe, so a green probe cannot hide a broken eval", async () => {
  const previous = process.env.BRAHMA_ALLOW_SCLANG;
  process.env.BRAHMA_ALLOW_SCLANG = "1";

  try {
    // Probe under the same configuration the eval will run under, and after the
    // sandbox self-test has settled.
    const status = await waitForSandbox();
    const sclang = status.runtimes.sclang;
    const sandboxOk = status.sandbox.ok;

    const res = await fetch(url("/api/runtimes/sclang/eval"), {
      method: "POST",
      headers: humanHeaders(),
      body: JSON.stringify({ code: "1+1", timeoutMs: 20000 })
    });

    if (sclang.available && sandboxOk) {
      assert.equal(res.status, 200, "an available runtime must actually evaluate");
      const body = await res.json();
      assert.equal(body.ok, true, `eval failed: ${body.reason} ${body.stderr || ""}`.slice(0, 400));
      assert.match(String(body.stdout || ""), /^2$/m, "1+1 must both evaluate and report its value");
    } else {
      assert.ok([500, 503].includes(res.status), `unavailable runtime must refuse, got ${res.status}`);
      const body = await res.json();
      assert.ok(
        ["sclang_not_installed", "sandbox_unavailable", "exec_error"].includes(body.error),
        `untyped failure: ${body.error}`
      );
    }
  } finally {
    if (previous === undefined) delete process.env.BRAHMA_ALLOW_SCLANG;
    else process.env.BRAHMA_ALLOW_SCLANG = previous;
  }
});
