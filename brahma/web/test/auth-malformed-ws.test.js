"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { once } = require("node:events");
const WebSocket = require("ws");

test("auth: malformed WebSocket cookie cannot crash the gateway", { timeout: 8000 }, async (t) => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-malformed-auth-"));
  // A separate process proves a connection-handler exception cannot kill the
  // gateway, without letting the regression take down the test runner itself.
  const child = spawn(process.execPath, ["-e", `const s=require('./server');s.server.on('listening',()=>process.send({port:s.server.address().port}));`], {
    cwd: path.join(__dirname, ".."),
    env: {
      PATH: process.env.PATH, PORT: "0", HOST: "127.0.0.1",
      BRAHMA_RUNTIME_DIR: scratch, BRAHMA_OSC_LISTEN_PORT: "0", BRAHMA_DIRT_PORT: "57137",
      BRAHMA_HUMAN_TOKEN: "malformed-auth-test-human", BRAHMA_AGENT_TOKEN: "malformed-auth-test-agent"
    },
    stdio: ["ignore", "ignore", "pipe", "ipc"]
  });
  let stderr = "";
  child.stderr.on("data", (data) => { stderr += data; });
  const exited = once(child, "exit");
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
    await exited;
    fs.rmSync(scratch, { recursive: true, force: true });
  });
  const crashed = exited.then(([code, signal]) => {
    throw new Error(`gateway exited (${code || signal}): ${stderr}`);
  });
  // Keep the failure observable when the child exits between the two races.
  crashed.catch(() => {});
  const [{ port }] = await Promise.race([once(child, "message"), crashed]);
  const ws = new WebSocket(`ws://127.0.0.1:${port}`, {
    origin: `http://127.0.0.1:${port}`, headers: { cookie: "brahma_human=%" }
  });
  t.after(() => ws.terminate());
  ws.on("error", () => {});
  const response = new Promise((resolve) => ws.once("message", (data) => resolve(JSON.parse(data))));
  await Promise.race([once(ws, "open"), crashed]);
  ws.send(JSON.stringify({ type: "status" }));
  const frame = await Promise.race([response, crashed]);
  assert.equal(frame.type, "error");
  assert.equal(frame.code, "forbidden");
  const status = await fetch(`http://127.0.0.1:${port}/api/auth/status`).then((res) => res.json());
  assert.equal(status.authenticated, false);
});
