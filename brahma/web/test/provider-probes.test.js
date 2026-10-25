"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { once } = require("node:events");
const { createProviderRegistry } = require("../lib/agent/providers");

function fakeGhci(t, body) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-probe-"));
  fs.writeFileSync(path.join(dir, "ghci"), `#!/bin/sh\n${body}\n`, { mode: 0o700 });
  const oldPath = process.env.PATH;
  process.env.PATH = `${dir}:${oldPath}`;
  t.after(() => {
    process.env.PATH = oldPath;
    fs.rmSync(dir, { recursive: true, force: true });
  });
  return dir;
}

test("slow provider discovery returns immediately and reports pending honestly", async (t) => {
  fakeGhci(t, "sleep 0.6\nprintf 'TIDAL_OK\\n'");
  const start = performance.now();
  const registry = createProviderRegistry({ env: { ...process.env } });
  assert.ok(performance.now() - start < 300, "registry construction must not wait for ghci");
  const tidal = registry.list().find((p) => p.name === "tidal");
  assert.equal(tidal.available, false, "an installed executable is not a successful module probe");
  assert.match(tidal.reason, /not_probed|probing/);
  const result = await registry.probe();
  assert.equal(result.tidal, true);
  assert.equal(registry.list().find((p) => p.name === "tidal").reason, "ghc+tidal_module_present");
});

test("a failed probe cannot inherit availability from another registry", async (t) => {
  const dir = fakeGhci(t, "printf 'TIDAL_OK\\n'");
  const first = createProviderRegistry({ env: { ...process.env } });
  assert.equal((await first.probe()).tidal, true);
  fs.writeFileSync(path.join(dir, "ghci"), "#!/bin/sh\nexit 1\n", { mode: 0o700 });
  const second = createProviderRegistry({ env: { ...process.env } });
  assert.equal((await second.probe()).tidal, false);
  const tidal = second.list().find((p) => p.name === "tidal");
  assert.equal(tidal.available, false);
  assert.match(tidal.reason, /probe_failed|not_installed/);
  assert.equal(first.list().find((p) => p.name === "tidal").available, true);
});

test("overlapping capability refreshes share a bounded subprocess", async (t) => {
  const dir = fakeGhci(t, "printf 'probe\\n' >> \"$0.calls\"\nsleep 0.1\nprintf 'TIDAL_OK\\n'");
  const registry = createProviderRegistry({ env: { ...process.env } });
  const results = await Promise.all([registry.probe(), registry.probe()]);
  assert.equal(results[0].tidal, true);
  assert.equal(results[1].tidal, true);
  assert.equal(fs.readFileSync(path.join(dir, "ghci.calls"), "utf8"), "probe\n");
});

test("HTTP binds and serves provider status while ghci is still pending", async (t) => {
  const dir = fakeGhci(t, 'while [ ! -f "$0.release" ]; do sleep 0.05; done\nprintf "TIDAL_OK\\n"');
  const child = spawn(process.execPath, ["server.js"], {
    cwd: path.resolve(__dirname, ".."),
    env: {
      ...process.env, PORT: "0", HOST: "127.0.0.1", BRAHMA_OSC_LISTEN_PORT: "0",
      BRAHMA_DIRT_PORT: "57991", BRAHMA_OSC_SEND_PORT: "9",
      BRAHMA_AGENT_TOKEN: "probe-test-agent-token", BRAHMA_HUMAN_TOKEN: "probe-test-human-token",
      BRAHMA_RUNTIME_DIR: path.join(dir, "runtime")
    },
    detached: true,
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", (data) => { output += data; });
  child.stderr.on("data", (data) => { output += data; });
  const exit = once(child, "exit");
  try {
    const deadline = Date.now() + 5000;
    let match;
    while (!(match = /VISUAL CORTEX ONLINE: (http:\/\/127\.0\.0\.1:\d+)/.exec(output))) {
      assert.equal(child.exitCode, null, output);
      assert.ok(Date.now() < deadline, "HTTP must bind before ghci completes");
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    const response = await fetch(`${match[1]}/api/agent/providers`, {
      headers: { authorization: "Bearer probe-test-agent-token" },
      signal: AbortSignal.timeout(1000)
    });
    assert.equal(response.status, 200);
    const tidal = (await response.json()).providers.find((p) => p.name === "tidal");
    assert.equal(tidal.available, false);
    assert.match(tidal.reason, /not_probed|probing/);
  } finally {
    // This process group is created by this test; no unrelated server is touched.
    try { process.kill(-child.pid, "SIGKILL"); } catch (error) {
      if (error.code !== "ESRCH") throw error;
    }
    await exit;
  }
});
