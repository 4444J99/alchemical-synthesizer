"use strict";
const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const staticFixture = fs.mkdtempSync(path.join(os.tmpdir(), "aether-http-"));
fs.writeFileSync(path.join(staticFixture, "index.html"), "player");
process.env.AETHER_STATIC_DIR = staticFixture;
after(() => fs.rmSync(staticFixture, { recursive: true, force: true }));
const { safeResolve } = require("./serve");

test("static resolution rejects malformed URLs, traversal and escaped symlinks", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "aether-path-"));
  try {
    const root = path.join(tmp, "public");
    fs.mkdirSync(root);
    fs.writeFileSync(path.join(root, "index.html"), "player");
    fs.writeFileSync(path.join(tmp, "secret"), "private");
    fs.symlinkSync(path.join(tmp, "secret"), path.join(root, "escape"));
    fs.symlinkSync(tmp, path.join(root, "escape-dir"));
    fs.symlinkSync(path.join(root, "index.html"), path.join(root, "internal"));
    fs.mkdirSync(path.join(root, "nested"));
    fs.symlinkSync(path.join(tmp, "secret"), path.join(root, "nested", "index.html"));
    assert.equal(safeResolve(root, "/index.html?x=1"), fs.realpathSync(path.join(root, "index.html")));
    assert.equal(safeResolve(root, "/internal"), fs.realpathSync(path.join(root, "index.html")));
    for (const url of ["/%", "/%00", "/../secret", "/%2e%2e/secret", "/escape", "/escape-dir/secret", "/nested/", "/missing"]) {
      assert.equal(safeResolve(root, url), null, url);
    }
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
});


test("malformed HTTP paths fail without losing server liveness", { timeout: 5000 }, async () => {
  const { server } = require("./serve");
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const rejected = await fetch(base + "/%");
    assert.equal(rejected.status, 404);
    await rejected.text();
    const health = await fetch(base + "/healthz");
    assert.equal(health.status, 200);
    assert.equal((await health.json()).ok, true);
    const player = await fetch(base + "/");
    assert.equal(player.status, 200);
    assert.match(player.headers.get("content-type"), /text\/html/);
    await player.text();
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});
