"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
test("key identity and revocation stay bound to the authenticated account", { timeout: 10000 }, async () => {
  const data = fs.mkdtempSync(path.join(os.tmpdir(), "foundry-accounts-"));
  process.env.FOUNDRY_DATA_DIR = data;
  const licensing = require("../auth/licensing");
  const alice = licensing.issueApiKey("alice@example.test", "free", "alice");
  const bob = licensing.issueApiKey("bob@example.test", "free", "bob");
  const express = require("express");
  const app = express();
  app.use("/api/v1", require("./rest"));
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/v1`;
  try {
    const queryOnly = await fetch(base + "/account/usage?api_key=" + encodeURIComponent(alice.key));
    assert.equal(queryOnly.status, 401);
    await queryOnly.text();
    const headerKey = await fetch(base + "/account/usage", { headers: { "x-api-key": alice.key } });
    assert.equal(headerKey.status, 200);
    await headerKey.text();
    const headers = { Authorization: "Bearer " + alice.key, "content-type": "application/json" };
    const usage = await fetch(base + "/account/usage", { headers });
    assert.equal((await usage.json()).data.ownerEmail, "alice@example.test");
    const denied = await fetch(base + "/account/keys/revoke", { method: "POST", headers, body: JSON.stringify({ key: bob.key }) });
    assert.equal(denied.status, 403);
    await denied.text();
    assert.ok(licensing.resolveApiKey(bob.key));
    const allowed = await fetch(base + "/account/keys/revoke", { method: "POST", headers, body: JSON.stringify({ key: alice.key }) });
    assert.equal(allowed.status, 200);
    await allowed.text();
    assert.equal(licensing.resolveApiKey(alice.key), null);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(data, { recursive: true, force: true });
  }
});
