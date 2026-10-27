"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { spawnSync } = require("node:child_process");

test("ownership: authenticated identity is preserved across every specimen surface", async (t) => {
  const data = fs.mkdtempSync(path.join(os.tmpdir(), "foundry-ownership-"));
  process.env.FOUNDRY_DATA_DIR = data;
  const licensing = require("../auth/licensing");
  const store = require("../core/store");
  const alice = licensing.issueApiKey("alice@example.test", "creator", "alice");
  const bob = licensing.issueApiKey("bob@example.test", "creator", "bob");
  const express = require("express");
  const app = express();
  app.use("/api/v1", require("./rest")); app.use("/mcp", require("./mcp")); app.use("/acp", require("./acp"));
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = (route, body, key = alice.key) => fetch(base + route, { method: "POST",
    headers: { authorization: "Bearer " + key, "content-type": "application/json" }, body: JSON.stringify(body) });
  const args = { module: "Azoth", creator: "A display alias", ownerEmail: "bob@example.test" };
  try {
    await t.test("REST, MCP, and both HTTP ACP adapters derive ownership from the key", async () => {
      const rest = await (await post("/api/v1/render", args)).json();
      assert.equal(rest.data.specimen.ownerEmail, "alice@example.test");
      const mcp = await (await post("/mcp", { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "render_specimen", arguments: args } })).json();
      assert.equal(mcp.result.structuredContent.ownerEmail, "alice@example.test");
      const prompt = JSON.stringify({ action: "render_specimen", args });
      const comm = await (await post("/acp/runs", { input: prompt })).json();
      assert.equal(JSON.parse(comm.output[0].parts[0].content).ownerEmail, "alice@example.test");
      const client = await (await post("/acp/jsonrpc", { jsonrpc: "2.0", id: 2, method: "session/prompt", params: { prompt } })).json();
      assert.equal(JSON.parse(client.result.content[0].text).ownerEmail, "alice@example.test");
    });
    await t.test("native ACP stdio carries the same authenticated ownership", () => {
      store.flushSync();
      const childData = path.join(data, "stdio"); fs.mkdirSync(childData);
      fs.copyFileSync(store.DB_PATH, path.join(childData, "store.json"));
      const prompt = JSON.stringify({ action: "render_specimen", args });
      const child = spawnSync(process.execPath, [path.resolve(__dirname, "../../bin/acp-stdio.js")], {
        env: { ...process.env, FOUNDRY_DATA_DIR: childData, BRAHMA_API_KEY: alice.key },
        input: JSON.stringify({ jsonrpc: "2.0", id: 3, method: "session/prompt", params: { prompt } }) + "\n",
        encoding: "utf8", timeout: 5000
      });
      assert.equal(child.status, 0, child.stderr);
      const reply = JSON.parse(child.stdout.trim());
      assert.equal(JSON.parse(reply.result.content[0].text).ownerEmail, "alice@example.test");
    });
    await t.test("only the owner can list or unlist; listing never transfers identity", async () => {
      const specimens = store.collection("specimens");
      specimens.insert({ id: "owned", ownerEmail: "alice@example.test", creator: "A display alias", simulated: false,
        audioUrl: "fixture.wav", forSale: true, priceCents: 100, createdAt: new Date().toISOString() });
      for (const action of ["list", "unlist"]) {
        const res = await post(`/api/v1/specimens/owned/${action}`, { ownerEmail: "bob@example.test", priceCents: 1 }, bob.key);
        assert.equal(res.status, 403); await res.text();
      }
      assert.equal(specimens.find((s) => s.id === "owned").ownerEmail, "alice@example.test");
      let res = await post("/api/v1/specimens/owned/list", { priceCents: 250 });
      assert.equal(res.status, 200); await res.text();
      const row = specimens.find((s) => s.id === "owned");
      assert.equal(row.creator, "A display alias"); assert.equal(row.priceCents, 250);
      res = await post("/api/v1/specimens/owned/unlist", {});
      assert.equal(res.status, 200); await res.text(); assert.equal(row.forSale, false);
    });
    await t.test("legacy unowned records and simulated specimens cannot become sale listings", async () => {
      const specimens = store.collection("specimens");
      specimens.insert({ id: "legacy", creator: "alice@example.test", simulated: false, audioUrl: "fixture.wav", forSale: false });
      specimens.insert({ id: "simulated", ownerEmail: "alice@example.test", simulated: true, audioUrl: null, forSale: false });
      for (const [id, status] of [["legacy", 403], ["simulated", 400]]) {
        const res = await post(`/api/v1/specimens/${id}/list`, { priceCents: 100 });
        assert.equal(res.status, status); await res.text();
        assert.equal(specimens.find((s) => s.id === id).forSale, false);
      }
    });
  } finally {
    server.closeAllConnections(); await new Promise((resolve) => server.close(resolve));
    store.flushSync(); fs.rmSync(data, { recursive: true, force: true });
  }
});
