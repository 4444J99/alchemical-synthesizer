"use strict";

// Regression: a signalled gateway must exit even while a WebSocket client is
// connected. server.js used to install SIGTERM/SIGINT handlers that closed the
// listeners but never exited. `wss.close()` leaves connected clients open and an
// open upgraded socket keeps `http.Server#close()` from calling back, so a
// signalled process ran on indefinitely and ignored every later SIGTERM. Two
// orphaned `node --test test/auth.test.js` runs sat in that state for 8.5 days.

const test = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const dgram = require("node:dgram");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const WebSocket = require("ws");

const SERVER = path.join(__dirname, "..", "server.js");
const BOOT_TIMEOUT_MS = 20000;
const EXIT_TIMEOUT_MS = 5000;

// The server treats a port of 0 as "use the default", so ask the kernel for free
// UDP ports instead; this keeps the child off 57122/57130 and off other tests.
function freeUdpPort() {
  return new Promise((resolve, reject) => {
    const socket = dgram.createSocket("udp4");
    socket.once("error", reject);
    socket.bind(0, "127.0.0.1", () => {
      const { port } = socket.address();
      socket.close(() => resolve(port));
    });
  });
}

async function startGateway(runtimeDir) {
  const env = {
    ...process.env,
    PORT: "0",
    HOST: "127.0.0.1",
    BRAHMA_HUMAN_TOKEN: "shutdown-human-token-1234567890123456",
    BRAHMA_AGENT_TOKEN: "shutdown-agent-token-1234567890123456",
    BRAHMA_RUNTIME_DIR: runtimeDir,
    BRAHMA_OSC_LISTEN_PORT: String(await freeUdpPort()),
    BRAHMA_DIRT_PORT: String(await freeUdpPort())
  };
  const child = spawn(process.execPath, [SERVER], { env, stdio: ["ignore", "pipe", "pipe"] });
  child.exited = new Promise((resolve) => {
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });

  let output = "";
  const port = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`gateway did not report a listening port within ${BOOT_TIMEOUT_MS}ms:\n${output}`));
    }, BOOT_TIMEOUT_MS);
    const onData = (chunk) => {
      output += chunk;
      const match = /VISUAL CORTEX ONLINE: http:\/\/127\.0\.0\.1:(\d+)/.exec(output);
      if (match) {
        clearTimeout(timer);
        resolve(Number(match[1]));
      }
    };
    child.stdout.on("data", onData);
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.once("exit", (code, signal) => {
      clearTimeout(timer);
      reject(new Error(`gateway exited during boot (code ${code}, signal ${signal}):\n${output}`));
    });
  });
  return { child, port };
}

function connect(port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`, {
      headers: { Origin: `http://127.0.0.1:${port}` }
    });
    ws.once("open", () => resolve(ws));
    ws.once("error", reject);
  });
}

for (const signal of ["SIGTERM", "SIGINT"]) {
  test(`gateway exits on ${signal} while a WebSocket client is connected`, async () => {
    const runtimeDir = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-shutdown-"));
    const { child, port } = await startGateway(runtimeDir);
    let ws = null;
    try {
      ws = await connect(port);
      child.kill(signal);
      let deadline;
      const result = await Promise.race([
        child.exited,
        new Promise((resolve) => { deadline = setTimeout(() => resolve(null), EXIT_TIMEOUT_MS); })
      ]);
      clearTimeout(deadline);
      assert.ok(result, `gateway still running ${EXIT_TIMEOUT_MS}ms after ${signal} with a client attached`);
      // A drained stop is a clean exit, not a kill: status 0, no terminating signal.
      assert.deepEqual(result, { code: 0, signal: null });
    } finally {
      if (ws) ws.terminate();
      child.kill("SIGKILL");
      await child.exited;
      fs.rmSync(runtimeDir, { recursive: true, force: true });
    }
  });
}
