"use strict";

// Regression for the signal path with work in flight. A SIGTERM/SIGINT that arrives
// while a render is running must cancel the render and its descendants, wait for them
// to settle, exit 0, and give any second signal back to the default action. The first
// version of the signal handler exited as soon as the HTTP server closed, which would
// have left a detached renderer running after the gateway reported a clean stop.

const test = require("node:test");
const assert = require("node:assert/strict");
const dgram = require("node:dgram");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");

const EVENTS = [{ time: 0, note: 60, vel: 0.8, dur: 0.2 }];

let gateway = null;
let scratch = null;
let pidFiles = [];
const saved = {};

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

async function waitFor(check, message, timeout = 5000) {
  const deadline = Date.now() + timeout;
  while (!check()) {
    if (Date.now() >= deadline) throw new Error(message);
    await delay(10);
  }
}

function within(promise, ms, message) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(message)), ms); })
  ]).finally(() => clearTimeout(timer));
}

const ourHandlers = (signal) => process.listeners(signal).filter((fn) => fn.name === "stopOnSignal");

test.before(async () => {
  scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-shutdown-render-"));
  const bin = path.join(scratch, "bin");
  fs.mkdirSync(bin);
  const parentFile = path.join(scratch, "sclang.pid");
  const childFile = path.join(scratch, "synth.pid");
  pidFiles = [parentFile, childFile];
  const heartbeat = path.join(scratch, "heartbeat");
  // A fake renderer: sclang spawns a descendant that writes a heartbeat until killed.
  const childCode = `const fs=require('node:fs');fs.writeFileSync(${JSON.stringify(childFile)},String(process.pid));setInterval(()=>fs.appendFileSync(${JSON.stringify(heartbeat)},'.'),10);`;
  const parentCode = `const fs=require('node:fs');fs.writeFileSync(${JSON.stringify(parentFile)},String(process.pid));require('node:child_process').spawn(process.execPath,['-e',${JSON.stringify(childCode)}],{stdio:['ignore','inherit','inherit']});setInterval(()=>{},1000);`;
  fs.writeFileSync(path.join(bin, "sclang"), `#!/usr/bin/env node\n${parentCode}\n`, { mode: 0o700 });
  fs.writeFileSync(path.join(bin, "scsynth"), "#!/bin/sh\nexit 0\n", { mode: 0o700 });

  const env = {
    PATH: `${bin}${path.delimiter}${process.env.PATH}`,
    TMPDIR: scratch,
    PORT: "0",
    HOST: "127.0.0.1",
    BRAHMA_HUMAN_TOKEN: "shutdown-human-token-1234567890123456",
    BRAHMA_AGENT_TOKEN: "shutdown-agent-token-1234567890123456",
    BRAHMA_RUNTIME_DIR: path.join(scratch, "runtime"),
    BRAHMA_OSC_LISTEN_PORT: String(await freeUdpPort()),
    BRAHMA_DIRT_PORT: String(await freeUdpPort())
  };
  for (const [key, value] of Object.entries(env)) {
    saved[key] = process.env[key];
    process.env[key] = value;
  }
  gateway = require("../server");
});

test.after(() => {
  for (const file of pidFiles) {
    if (!fs.existsSync(file)) continue;
    try { process.kill(Number(fs.readFileSync(file, "utf8")), "SIGKILL"); } catch (_) {}
  }
  for (const [key, value] of Object.entries(saved)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  if (scratch) fs.rmSync(scratch, { recursive: true, force: true });
});

test("a signal cancels an active render, waits for it, exits 0 and releases both handlers",
  { skip: process.platform === "win32" }, async (t) => {
    const heartbeat = path.join(scratch, "heartbeat");
    const exit = new Promise((resolve) => { t.mock.method(process, "exit", (code) => resolve(code)); });

    const queued = gateway.agent.runner.enqueue({ tool: "render_pattern", args: { events: EVENTS, duration: 1 } });
    assert.equal(queued.ok, true, JSON.stringify(queued));
    await waitFor(() => fs.existsSync(heartbeat), "renderer fixture did not start");
    assert.equal(ourHandlers("SIGTERM").length, 1);
    assert.equal(ourHandlers("SIGINT").length, 1);

    // Call the gateway's own handler; emitting the event would also run the test
    // runner's termination handler.
    ourHandlers("SIGTERM")[0]();

    const code = await within(exit, 5000, "gateway did not exit after the signal");
    assert.equal(code, 0);

    const job = gateway.agent.runner.get(queued.job.id);
    assert.equal(job.state, "failed", "the render must be cancelled before the gateway exits");
    assert.equal(job.error, "stopped by human");
    const size = fs.statSync(heartbeat).size;
    await delay(120);
    assert.equal(fs.statSync(heartbeat).size, size, "the renderer outlived the gateway's shutdown");

    assert.equal(ourHandlers("SIGTERM").length, 0, "the handler must release SIGTERM");
    assert.equal(ourHandlers("SIGINT").length, 0, "a second signal of the other kind must take the default action");
  });
