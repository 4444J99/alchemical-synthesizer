"use strict";
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const http = require("node:http");

const fixture = fs.mkdtempSync(path.join(os.tmpdir(), "foundry-audio-"));
const specimens = path.join(fixture, "specimens");
fs.mkdirSync(specimens);
fs.writeFileSync(path.join(specimens, "sample.wav"), "0123456789");
fs.writeFileSync(path.join(specimens, "empty.wav"), "");
fs.writeFileSync(path.join(specimens, "fault.wav"), Buffer.alloc(256 * 1024, 7));
fs.mkdirSync(path.join(specimens, "directory.wav"));
fs.writeFileSync(path.join(fixture, "outside.wav"), "outside private fixture");
fs.mkdirSync(path.join(fixture, "specimens-sibling"));
fs.writeFileSync(path.join(fixture, "specimens-sibling", "private.wav"), "private sibling fixture");
fs.symlinkSync(path.join(fixture, "outside.wav"), path.join(specimens, "escape.wav"));
fs.symlinkSync(path.join(fixture, "specimens-sibling"), path.join(specimens, "escape-dir"));
fs.symlinkSync(path.join(specimens, "sample.wav"), path.join(specimens, "inside.wav"));
process.env.FOUNDRY_DATA_DIR = path.join(fixture, "store");
process.env.BRAHMA_SPECIMENS_DIR = specimens;
const store = require("../core/store");
const express = require("express");
const app = express();
app.use("/api/v1", require("./rest"));
let server;
let base;

before(async () => {
  const rows = {
    sample: "sample.wav", empty: "empty.wav", fault: "fault.wav", directory: "directory.wav",
    escape: "escape.wav", escapeDir: "escape-dir/private.wav", inside: "inside.wav",
    traversal: "../outside.wav", missing: "missing.wav", invalid: "bad\0name.wav",
    remote: "https://cdn.example.test/sample.wav"
  };
  for (const [id, audioUrl] of Object.entries(rows)) {
    store.collection("specimens").insert({ id, audioUrl, simulated: false });
  }
  store.collection("specimens").insert({ id: "simulated", audioUrl: "sample.wav", simulated: true });
  server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  base = `http://127.0.0.1:${server.address().port}/api/v1/specimens`;
});

after(async () => {
  if (server) {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
  store.flushSync();
  fs.rmSync(fixture, { recursive: true, force: true });
});

async function read(id, options = {}) {
  const response = await fetch(`${base}/${id}/audio`, { signal: AbortSignal.timeout(1500), ...options });
  const body = await response.text();
  return { response, body };
}

test("regular specimen files and contained symlinks stream their exact bytes", async () => {
  for (const id of ["sample", "inside"]) {
    const { response, body } = await read(id);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "audio/wav");
    assert.equal(response.headers.get("accept-ranges"), "bytes");
    assert.equal(response.headers.get("content-length"), "10");
    assert.equal(body, "0123456789");
  }
});

test("canonical resolution rejects files outside the specimen directory", async () => {
  for (const id of ["escape", "escapeDir", "traversal"]) {
    const { response, body } = await read(id);
    assert.equal(response.status, 404, id);
    assert.equal(JSON.parse(body).error, "audio_file_missing");
  }
});

test("directories and unavailable paths fail safely", async () => {
  for (const id of ["directory", "missing", "invalid"]) {
    const { response, body } = await read(id);
    assert.equal(response.status, 404, id);
    assert.equal(JSON.parse(body).error, "audio_file_missing");
  }
});

test("single byte ranges return the requested inclusive bytes", async (t) => {
  const ranges = [
    ["bytes=2-5", "2345", "bytes 2-5/10"],
    ["bytes=6-", "6789", "bytes 6-9/10"],
    ["bytes=-3", "789", "bytes 7-9/10"],
    ["bytes=-20", "0123456789", "bytes 0-9/10"],
    ["bytes=8-100", "89", "bytes 8-9/10"],
    ["bytes=0-999999999999999999999", "0123456789", "bytes 0-9/10"],
    ["bytes=-999999999999999999999", "0123456789", "bytes 0-9/10"],
    ["BYTES=0-0", "0", "bytes 0-0/10"],
    ["bytes= 1-2", "12", "bytes 1-2/10"]
  ];
  for (const [range, expectedBody, expectedRange] of ranges) {
    await t.test(range, async () => {
      const { response, body } = await read("sample", { headers: { Range: range } });
      assert.equal(response.status, 206);
      assert.equal(body, expectedBody);
      assert.equal(response.headers.get("content-range"), expectedRange);
      assert.equal(Number(response.headers.get("content-length")), expectedBody.length);
    });
  }
});

test("malformed and unsatisfiable byte ranges return explicit 416 responses", async (t) => {
  const ranges = [
    "nonsense", "bytes=-", "bytes=1-2 trailing", "bytes=1x-2",
    "bytes=-0", "bytes=10-", "bytes=7-2", "bytes=999999999999999999999-"
  ];
  for (const range of ranges) {
    await t.test(range, async () => {
      const { response, body } = await read("sample", { headers: { Range: range } });
      assert.equal(response.status, 416);
      assert.equal(response.headers.get("content-range"), "bytes */10");
      assert.equal(body, "");
    });
  }
});

test("unsupported range units and multipart requests fall back to the full representation", async () => {
  for (const range of ["items=0-1", "bytes=0-1,4-5"]) {
    const { response, body } = await read("sample", { headers: { Range: range } });
    assert.equal(response.status, 200, range);
    assert.equal(response.headers.get("content-range"), null);
    assert.equal(body, "0123456789");
  }
});

test("HEAD ignores Range and describes the full representation without a body", async () => {
  const { response, body } = await read("sample", { method: "HEAD", headers: { Range: "bytes=0-1" } });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-length"), "10");
  assert.equal(response.headers.get("content-range"), null);
  assert.equal(body, "");
});

test("If-Range falls back to a complete response when no validator has been established", async () => {
  for (const validator of ['"previous-version"', "Wed, 21 Oct 2015 07:28:00 GMT"]) {
    const { response, body } = await read("sample", { headers: { Range: "bytes=0-1", "If-Range": validator } });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-range"), null);
    assert.equal(body, "0123456789");
  }
});

test("empty files ignore ranges and return a complete zero-length representation", async () => {
  for (const headers of [{}, { Range: "bytes=-1" }, { Range: "bytes=0-" }]) {
    const { response, body } = await read("empty", { headers });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-length"), "0");
    assert.equal(response.headers.get("content-range"), null);
    assert.equal(body, "");
  }
});

test("simulation is unavailable and remote artifacts redirect without fetching", async () => {
  const simulated = await read("simulated");
  assert.equal(simulated.response.status, 409);
  const remote = await read("remote", { redirect: "manual" });
  assert.equal(remote.response.status, 302);
  assert.equal(remote.response.headers.get("location"), "https://cdn.example.test/sample.wav");
});

test("a read error before response bytes returns a controlled failure", async (t) => {
  const createReadStream = fs.createReadStream;
  t.mock.method(fs, "createReadStream", (file, options) => {
    const stream = createReadStream(file, options);
    if (path.basename(file) === "fault.wav") {
      queueMicrotask(() => stream.destroy(Object.assign(new Error("fixture read failure"), { code: "EIO" })));
    }
    return stream;
  });
  const { response, body } = await read("fault", { headers: { Range: "bytes=0-7" } });
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("content-range"), null);
  assert.match(response.headers.get("content-type"), /^application\/json/);
  assert.equal(JSON.parse(body).error, "audio_file_missing");
});

test("a read error after response bytes terminates the stream without crashing the server", async (t) => {
  const createReadStream = fs.createReadStream;
  t.mock.method(fs, "createReadStream", (file, options) => {
    const stream = createReadStream(file, options);
    if (path.basename(file) === "fault.wav") {
      stream.once("data", () => queueMicrotask(() => stream.destroy(new Error("fixture late read failure"))));
    }
    return stream;
  });
  const result = await new Promise((resolve, reject) => {
    const request = http.get(`${base}/fault/audio`, (response) => {
      let bytes = 0;
      response.on("data", (chunk) => { bytes += chunk.length; });
      response.on("aborted", () => resolve({ status: response.statusCode, bytes, complete: response.complete }));
      response.on("end", () => resolve({ status: response.statusCode, bytes, complete: response.complete }));
      response.on("error", () => {});
    });
    request.on("error", reject);
    request.setTimeout(1500, () => request.destroy(new Error("audio stream hung")));
  });
  assert.equal(result.status, 200);
  assert.ok(result.bytes > 0 && result.bytes < 256 * 1024);
  assert.equal(result.complete, false);
  const healthy = await read("sample");
  assert.equal(healthy.response.status, 200);
  assert.equal(healthy.body, "0123456789");
});
