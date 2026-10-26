"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

test("edge host exposes only listener artifacts, including when private records already exist in R2", async () => {
  // Keep the real fetch handler; substitute only the Cloudflare platform adapter.
  const source = fs.readFileSync(path.join(__dirname, "worker.mjs"), "utf8")
    .replace('import { Container, getContainer } from "@cloudflare/containers";',
      "class Container {}\nfunction getContainer(binding) { return binding; }");
  const { default: worker } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);
  const reads = [];
  const proxies = [];
  const env = {
    SEGMENTS: { async get(key) { reads.push(key); return { body: key, httpEtag: "fixture", writeHttpMetadata() {} }; } },
    AETHER_CONTAINER: { async fetch(request) { proxies.push(new URL(request.url).pathname); return new Response("container"); } }
  };
  for (const key of ["stream.m3u8", "seg_00001.ts", "telemetry.json", "lineage.json"]) {
    const response = await worker.fetch(new Request(`https://radio.invalid/live/${key}`), env);
    assert.equal(response.status, 200);
    assert.equal(await response.text(), key);
  }
  for (const key of ["queue/sub_00001.json", "%71ueue/sub_00001.json", "queue/.seq", "organism.json", "stream.m3u8.state.json", "%", "x/seg_1.ts"]) {
    const response = await worker.fetch(new Request(`https://radio.invalid/live/${key}`), env);
    assert.equal(response.status, 404, key);
  }
  assert.deepEqual(reads, ["stream.m3u8", "seg_00001.ts", "telemetry.json", "lineage.json"]);
  assert.deepEqual(proxies, [], "private live paths must not bypass the R2 gate through the container");
  assert.equal((await worker.fetch(new Request("https://radio.invalid/"), env)).status, 200);
  assert.deepEqual(proxies, ["/"]);
});
