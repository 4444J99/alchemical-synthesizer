"use strict";

const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawn } = require("node:child_process");
const { once } = require("node:events");
const root = path.resolve(__dirname, "../..");
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), "aether-integration-"));
process.env.AETHER_LIVE_DIR = path.join(fixture, "live");
process.env.AETHER_SUBMIT_TOKEN = "fixture-operator-token-not-a-production-secret";
delete process.env.AETHER_STATIC_DIR;
delete process.env.AETHER_TOOLS_DIR;
after(() => fs.rmSync(fixture, { recursive: true, force: true }));

test("every Docker COPY input exists in its declared repository context", () => {
  const dockerfile = fs.readFileSync(path.join(__dirname, "Dockerfile"), "utf8");
  for (const line of dockerfile.split("\n").filter((l) => l.startsWith("COPY "))) {
    for (const input of line.split(/\s+/).slice(1, -1)) {
      assert.ok(fs.existsSync(path.join(root, input)), `missing Docker input: ${input}`);
    }
  }
});

test("local stream host serves bundled listener and accepts authenticated operator intake", async () => {
  const { server } = require("./serve");
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const page = await fetch(base + "/");
    assert.equal(page.status, 200);
    assert.match(await page.text(), /AETHER/);
    const queued = await fetch(base + "/submit", {
      method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${process.env.AETHER_SUBMIT_TOKEN}` },
      body: JSON.stringify({ url: "https://example.invalid/test.wav", license: "unknown" })
    });
    assert.equal(queued.status, 200);
    assert.ok((await queued.json()).id);
    const files = fs.readdirSync(path.join(fixture, "live", "queue"));
    assert.ok(files.length > 0, "submission must reach the actual queue");
    const nullBody = await fetch(base + "/submit", {
      method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${process.env.AETHER_SUBMIT_TOKEN}` }, body: "null"
    });
    assert.equal(nullBody.status, 400, "invalid JSON shape must not crash the host");
    const health = await fetch(base + "/healthz");
    assert.equal(health.status, 200);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});

async function startHost(file, extraEnv = {}) {
  const env = { ...process.env, ...extraEnv };
  for (const key of ["AETHER_LIVE_DIR", "AETHER_STATIC_DIR", "AETHER_TOOLS_DIR"]) delete env[key];
  const child = spawn(process.execPath, ["-e", `const {server}=require(${JSON.stringify(file)}); server.listen(0,'127.0.0.1',()=>console.log(server.address().port));`],
    { env, stdio: ["ignore", "pipe", "pipe"] });
  let stderr = "";
  child.stderr.on("data", (b) => { stderr += b; });
  const base = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { child.kill(); reject(new Error("host did not start: " + stderr)); }, 5000);
    child.once("exit", (code) => { clearTimeout(timeout); reject(new Error(`host exited ${code}: ${stderr}`)); });
    child.stdout.once("data", (data) => { clearTimeout(timeout); resolve(`http://127.0.0.1:${Number(data.toString().trim())}`); });
  });
  return { base, child, async close() { if (child.exitCode !== null || child.signalCode) return; const done = once(child, "exit"); child.kill(); await done; } };
}

test("broadcast and host share the same repository out/live with zero path overrides", { timeout: 20000 }, async () => {
  const copy = path.join(fixture, "checkout");
  fs.cpSync(path.join(root, "aether"), path.join(copy, "aether"), { recursive: true });
  fs.mkdirSync(path.join(copy, "brahma"), { recursive: true });
  const env = { ...process.env };
  delete env.AETHER_LIVE_DIR;
  execFileSync("bash", [path.join(copy, "aether/tools/broadcast.sh"), "--segments", "1", "--seconds", "1", "--no-nrt"],
    { cwd: copy, env, timeout: 12000, stdio: "pipe" });
  assert.ok(fs.existsSync(path.join(copy, "out/live/stream.m3u8")));
  assert.ok(fs.existsSync(path.join(copy, "out/live/telemetry.json")));
  const host = await startHost(path.join(copy, "aether/deploy/serve.js"));
  try {
    const stream = await fetch(host.base + "/live/stream.m3u8");
    assert.equal(stream.status, 200);
    assert.match(await stream.text(), /#EXTM3U/);
    const queued = await fetch(host.base + "/submit", {
      method: "POST", headers: { authorization: `Bearer ${process.env.AETHER_SUBMIT_TOKEN}` },
      body: JSON.stringify({ url: "https://example.invalid/test.wav" })
    });
    assert.equal(queued.status, 200);
    const { id } = await queued.json();
    assert.ok(fs.existsSync(path.join(copy, "out/live/queue", id + ".json")));
    for (const url of [`/live/queue/${id}.json`, `/live/%71ueue/${id}.json`, "/live/queue/.seq", "/live/stream.m3u8.state.json"]) {
      assert.equal((await fetch(host.base + url)).status, 404, url + " must stay private");
    }
  } finally { await host.close(); }
});

test("malformed submission fields cannot terminate the host", { timeout: 12000 }, async () => {
  const host = await startHost(path.join(__dirname, "serve.js"));
  try {
    for (const body of [null, [], { url: { toString: null } }, { url: "https://example.invalid/\u0000.wav" },
      { url: "https://example.invalid/a", license: { toString: null } },
      { url: "https://example.invalid/a", attribution: ["bad"] },
      { url: "http://" }, { url: "https://user:password@example.invalid/a" }]) {
      const response = await fetch(host.base + "/submit", {
        method: "POST", headers: { authorization: `Bearer ${process.env.AETHER_SUBMIT_TOKEN}` }, body: JSON.stringify(body)
      });
      assert.equal(response.status, 400, JSON.stringify(body));
      assert.equal((await fetch(host.base + "/healthz")).status, 200);
    }
  } finally { await host.close(); }
});

test("network intake is disabled by default and otherwise requires the operator token", { timeout: 10000 }, async () => {
  for (const token of ["", "operator-test-token"]) {
    const host = await startHost(path.join(__dirname, "serve.js"), { AETHER_SUBMIT_TOKEN: token });
    try {
      for (const authorization of ["", "Bearer wrong-token"]) {
        const response = await fetch(host.base + "/submit", {
          method: "POST", headers: { authorization }, body: JSON.stringify({ url: "https://example.invalid/test.wav" })
        });
        assert.equal(response.status, token ? 401 : 503);
      }
    } finally { await host.close(); }
  }
});
