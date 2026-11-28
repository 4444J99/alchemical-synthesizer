"use strict";

// Boots the gateway in-process against a fake renderer, for the shutdown tests.
// `sclang` is a script that spawns a descendant writing a heartbeat until it is
// killed, so a test can tell whether a cancelled render's processes are really gone.
// Each test file runs in its own process, so each gets its own gateway instance.

const dgram = require("node:dgram");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");

const EVENTS = [{ time: 0, note: 60, vel: 0.8, dur: 0.2 }];

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

/** Handlers the gateway registered for a signal (the test runner has its own). */
const gatewayHandlers = (signal) => process.listeners(signal).filter((fn) => fn.name === "stopOnSignal");

async function bootGateway({ graceMs } = {}) {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-shutdown-render-"));
  const bin = path.join(scratch, "bin");
  fs.mkdirSync(bin);
  const parentFile = path.join(scratch, "sclang.pid");
  const childFile = path.join(scratch, "synth.pid");
  const heartbeat = path.join(scratch, "heartbeat");
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
  if (graceMs !== undefined) env.BRAHMA_SHUTDOWN_GRACE_MS = String(graceMs);
  const saved = {};
  for (const [key, value] of Object.entries(env)) {
    saved[key] = process.env[key];
    process.env[key] = value;
  }
  const gateway = require("../../server");

  function cleanup() {
    for (const file of [parentFile, childFile]) {
      if (!fs.existsSync(file)) continue;
      try { process.kill(Number(fs.readFileSync(file, "utf8")), "SIGKILL"); } catch (_) {}
    }
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    fs.rmSync(scratch, { recursive: true, force: true });
  }

  return { gateway, heartbeat, cleanup };
}

module.exports = { EVENTS, bootGateway, gatewayHandlers, waitFor, within, delay };
