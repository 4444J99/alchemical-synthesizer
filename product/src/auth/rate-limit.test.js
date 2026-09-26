"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { rateLimit } = require("./rate-limit");
function request(middleware, peer, forwarded = "") {
  const result = { admitted: false, headers: {} };
  const res = { setHeader(k, v) { result.headers[k] = v; }, status(s) { result.status = s; return this; }, json(body) { result.body = body; } };
  middleware({ socket: { remoteAddress: peer }, headers: { "x-forwarded-for": forwarded } }, res, () => { result.admitted = true; });
  return result;
}
test("limits one peer, ignores spoofed forwarding, and recovers after expiry", () => {
  let time = 0;
  const limit = rateLimit({ limit: 2, windowMs: 1000, now: () => time });
  assert.equal(request(limit, "peer").admitted, true);
  assert.equal(request(limit, "peer").admitted, true);
  const rejected = request(limit, "peer", "different");
  assert.equal(rejected.status, 429);
  assert.equal(rejected.admitted, false);
  assert.equal(rejected.headers["Retry-After"], "1");
  assert.equal(request(limit, "other").admitted, true);
  time = 1000;
  assert.equal(request(limit, "peer").admitted, true);
});
test("bounded peer table refuses new identities without evicting live budgets", () => {
  let time = 0;
  const limit = rateLimit({ limit: 1, maxPeers: 1, windowMs: 1000, now: () => time });
  assert.equal(request(limit, "first").admitted, true);
  assert.equal(request(limit, "second").status, 429);
  assert.equal(request(limit, "first").status, 429);
  time = 1000;
  assert.equal(request(limit, "second").admitted, true);
});
test("bounded peer table removes entries that expire before the scheduled sweep", () => {
  let time = 0;
  const limit = rateLimit({ limit: 10, maxPeers: 2, windowMs: 1000, now: () => time });
  assert.equal(request(limit, "first").admitted, true);
  time = 600;
  assert.equal(request(limit, "second").admitted, true);
  time = 1000;
  assert.equal(request(limit, "third").admitted, true);
  time = 1600;
  assert.equal(request(limit, "fourth").admitted, true);
});
test("invalid limits fail at initialization", () => {
  for (const limit of [0, -1, Infinity, NaN, 1.5]) assert.throws(() => rateLimit({ limit }), TypeError);
});

test("REST admission covers both account routes and audio before expensive work", { timeout: 10000 }, async () => {
  const fs = require("node:fs");
  const data = fs.mkdtempSync(require("node:path").join(require("node:os").tmpdir(), "foundry-rate-"));
  process.env.FOUNDRY_DATA_DIR = data;
  const express = require("express");
  const app = express();
  app.use("/api/v1", require("../api/rest"));
  app.use((err, req, res, next) => res.status(400).json({ error: "invalid_json" }));
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/v1`;
  try {
    for (let i = 0; i < 11; i++) {
      const route = i % 2 ? "signup" : "login";
      const response = await fetch(`${base}/account/${route}`, { method: "POST", headers: { "content-type": "application/json", "x-forwarded-for": `spoof-${i}` }, body: "{" });
      assert.equal(response.status, i < 10 ? 400 : 429);
      await response.text();
    }
    for (let i = 0; i < 121; i++) {
      const response = await fetch(`${base}/specimens/missing/audio`);
      assert.equal(response.status, i < 120 ? 404 : 429);
      await response.text();
    }
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(data, { recursive: true, force: true });
  }
});
