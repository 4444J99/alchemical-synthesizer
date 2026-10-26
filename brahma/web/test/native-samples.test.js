"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
function api() {
  const filename = path.join(__dirname, "../lib/native-samples.js");
  assert.ok(fs.existsSync(filename), "native sample service must exist");
  return require(filename);
}
function wav(seconds = 1) {
  const data = Buffer.alloc(44 + 44100 * seconds * 4);
  data.write("RIFF"); data.writeUInt32LE(data.length - 8, 4); data.write("WAVEfmt ", 8);
  data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(2, 22);
  data.writeUInt32LE(44100, 24); data.writeUInt32LE(176400, 28);
  data.writeUInt16LE(4, 32); data.writeUInt16LE(16, 34); data.write("data", 36);
  data.writeUInt32LE(data.length - 44, 40);
  for (let i = 44; i < data.length; i += 2) data.writeInt16LE(Math.round(8000 * Math.sin(i / 17)), i);
  return data;
}
test("native sample admission validates actual PCM frames and content hashes", () => {
  const A = api(), bytes = wav();
  const hash = require("node:crypto").createHash("sha256").update(bytes).digest("hex");
  const admitted = A.admitAudio({ data: bytes.toString("base64"), sha256: hash });
  assert.equal(admitted.duration, 1);
  assert.equal(admitted.sha256, hash);
  for (const mutate of [b => b.subarray(0, 100), b => { b.writeUInt32LE(8000, 24); return b; },
    b => { b.writeUInt16LE(32, 34); return b; }]) {
    const bad = mutate(Buffer.from(bytes));
    assert.throws(() => A.admitAudio({ data: bad.toString("base64"), sha256: hash }), /PCM|hash|WAV|duration/i);
  }
  assert.throws(() => A.admitAudio({ data: "AA==", sha256: hash }), /WAV|PCM/i);
});

const os = require("node:os");
const crypto = require("node:crypto");
const catalogue = () => [{ name: "solve_pitch_shift", role: "audio_processor", audio_outputs: ["outBus"], control_outputs: [] }];
const body = () => { const bytes = wav(); return { module: "solve_pitch_shift", params: { semitones: -7 },
  audio: { data: bytes.toString("base64"), sha256: crypto.createHash("sha256").update(bytes).digest("hex") } }; };
function result(directory, job, donor, corrupt = false) {
  const output = path.join(directory, "result"); fs.mkdirSync(output);
  const bytes = wav(); fs.writeFileSync(path.join(output, job.module + ".wav"), bytes);
  fs.writeFileSync(path.join(output, "manifest.json"), JSON.stringify({ compile_exit_code: 0, donor: { sha256: donor.sha256 },
    native_rack_sha256: "a".repeat(64), modules: [{ name: job.module, status: "rendered", render_exit_code: 0,
      output: job.module + ".wav", output_sha256: corrupt ? "0".repeat(64) : crypto.createHash("sha256").update(bytes).digest("hex"),
      definition_sha256: "b".repeat(64), duration_seconds: 1, peak_dbfs: -6, rms_dbfs: -12 }] }));
  return output;
}
test("native jobs retain validated output and reject routing, simultaneous renders and corrupt results", async () => {
  const A = api(), root = fs.mkdtempSync(path.join(os.tmpdir(), "native-service-"));
  let finish;
  const gate = new Promise(resolve => { finish = resolve; });
  const service = A.createNativeService({ root, catalogue, render: async (dir, job, donor) => { await gate; return result(dir, job, donor); } });
  try {
    await assert.rejects(service.start({ ...body(), params: { outBus: 0 } }), /control/i);
    const job = await service.start(body());
    await assert.rejects(service.start(body()), /already rendering/i);
    finish(); await service.drain();
    assert.equal(service.get(job.id).state, "completed");
    assert.ok(fs.readFileSync(service.output(job.id)).equals(wav()));
    assert.equal(fs.statSync(path.dirname(path.dirname(service.output(job.id)))).mode & 0o777, 0o700);
    const broken = A.createNativeService({ root, catalogue, render: (dir, job, donor) => result(dir, job, donor, true) });
    const bad = await broken.start(body()); await broken.drain();
    assert.equal(broken.get(bad.id).state, "failed");
    assert.throws(() => broken.output(bad.id), /not ready/i);
  } finally { service.close(); await service.drain(); fs.rmSync(root, { recursive: true, force: true }); }
});
test("cancelled native jobs cannot become completed when a late render returns", async () => {
  const A = api(), root = fs.mkdtempSync(path.join(os.tmpdir(), "native-cancel-"));
  let finish, terminated = 0;
  const gate = new Promise(resolve => { finish = resolve; });
  const service = A.createNativeService({ root, catalogue, render: async (dir, job, donor, child) => {
    child({ terminate() { terminated++; } }); await gate; return result(dir, job, donor);
  } });
  try {
    const job = await service.start(body());
    service.cancel(job.id); finish(); await service.drain();
    assert.equal(service.get(job.id).state, "cancelled"); assert.equal(terminated, 1);
    assert.throws(() => service.output(job.id), /not ready/i);
  } finally { service.close(); await service.drain(); fs.rmSync(root, { recursive: true, force: true }); }
});
test("native routes require human role and trusted loopback Origin before reading uploaded audio", async () => {
  const express = require("express"), { createAuth } = require("../lib/auth");
  const app = express(); let server;
  const auth = createAuth({ getPort: () => server.address().port, humanToken: "human-fixture", agentToken: "agent-fixture" });
  app.use("/native", api().createNativeSamplesRouter({ auth, service: { catalogue: async () => catalogue() } }));
  server = app.listen(0, "127.0.0.1"); await new Promise(resolve => server.once("listening", resolve));
  const base = "http://127.0.0.1:" + server.address().port;
  try {
    for (const headers of [{}, { authorization: "Bearer agent-fixture" }, { cookie: "brahma_human=human-fixture", origin: "https://evil.test" }]) {
      const response = await fetch(base + "/native/jobs", { method: "POST", headers: { "content-type": "application/json", ...headers }, body: "invalid json" });
      assert.equal(response.status, 403);
    }
    const response = await fetch(base + "/native/catalogue", { headers: { cookie: "brahma_human=human-fixture", origin: base } });
    assert.equal(response.status, 200); assert.equal((await response.json()).modules[0].name, "solve_pitch_shift");
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test("installed Forge pipeline produces a measured native sound from admitted PCM", {
  skip: process.env.RUN_NATIVE_DONOR_TESTS !== "1" ? "set RUN_NATIVE_DONOR_TESTS=1 for installed SC" : false,
  timeout: 150000,
}, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "native-real-"));
  const service = api().createNativeService({ root });
  try {
    const job = await service.start(body()); await service.drain();
    const complete = service.get(job.id);
    assert.equal(complete.state, "completed", complete.error);
    assert.ok(Number.isFinite(complete.result.measurement.rmsDbfs));
    assert.ok(complete.result.measurement.peakDbfs > -60);
    assert.notEqual(complete.result.sha256, job.sourceSha256);
    assert.ok(Math.abs(complete.result.duration - 1) < .025);
  } finally { service.close(); await service.drain(); fs.rmSync(root, { recursive: true, force: true }); }
});
