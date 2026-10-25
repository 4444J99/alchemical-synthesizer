"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
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
