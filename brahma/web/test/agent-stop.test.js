"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");
const { createJobRunner } = require("../lib/agent/jobs");
const { createAgentLayer } = require("../lib/agent");
const { createTools, defaultExecFile } = require("../lib/agent/tools");
const { createAgentGateway } = require("../lib/mcp/client");
const { handleRpc } = require("../lib/mcp/server");

const REPO_ROOT = path.resolve(__dirname, "../../..");
const EVENTS = [{ time: 0, note: 60, vel: 0.8, dur: 0.2 }];

function deferred() {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return { promise, resolve };
}

async function accepted(layer) {
  const proposed = await layer.propose({ events: EVENTS });
  assert.equal(layer.accept(proposed.approval.id, { actor: "human" }).ok, true);
  return proposed.approval.id;
}

test("stop: cancellation before launch executes no command", async (t) => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-stop-"));
  t.after(() => fs.rmSync(scratch, { recursive: true, force: true }));
  let calls = 0;
  const layer = createAgentLayer({
    repoRoot: REPO_ROOT, scratchRoot: scratch, env: {},
    execFile: async () => { calls += 1; throw new Error("must not launch"); }
  });
  const id = await accepted(layer);
  const { job } = layer.run(id, { actor: "human" });

  assert.equal(layer.stop({ actor: "human" }).ok, true);
  await layer.runner.drain();
  assert.equal(calls, 0);
  assert.equal(layer.runner.get(job.id).state, "failed");
  assert.equal(layer.runner.get(job.id).error, "stopped by human");
  assert.equal(layer.approvals.get(id).state, "failed");
});

test("stop: active and queued approvals fail terminally despite late render success", async (t) => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-stop-"));
  t.after(() => fs.rmSync(scratch, { recursive: true, force: true }));
  const started = deferred();
  const finish = deferred();
  const commands = [];
  const layer = createAgentLayer({
    repoRoot: REPO_ROOT, scratchRoot: scratch, env: {},
    execFile: async (file, args) => {
      commands.push(file);
      if (file === "bash") {
        fs.writeFileSync(args[2], "fake wav");
        started.resolve();
        await finish.promise; // A late completion must not undo cancellation.
      } else {
        fs.writeFileSync(args.at(-1), "{}");
      }
      return { stdout: "", stderr: "" };
    }
  });
  const a = await accepted(layer);
  const b = await accepted(layer);
  layer.run(a, { actor: "human" });
  layer.run(b, { actor: "human" });
  await started.promise;
  try {
    assert.equal(layer.stop({ actor: "agent" }).code, "forbidden");
    assert.deepEqual(layer.runner.list().map((job) => job.state), ["running", "queued"]);
    const stopped = layer.stop({ actor: "human" });
    assert.equal(stopped.ok, true);
    assert.deepEqual(layer.runner.list().map((job) => job.state), ["failed", "failed"]);
    assert.deepEqual(layer.approvals.list().map((approval) => approval.state), ["failed", "failed"]);
    assert.equal(layer.runner.pending, 0);
    layer.stop({ actor: "human" }); // Repeated stop is harmless.
  } finally {
    finish.resolve();
    await layer.runner.drain();
  }
  assert.deepEqual(commands, ["bash"], "analysis and queued renders must not start after stop");
  assert.deepEqual(layer.runner.list().map((job) => [job.state, job.error, job.result]), [
    ["failed", "stopped by human", null], ["failed", "stopped by human", null]
  ]);
  assert.deepEqual(layer.approvals.list().map((approval) => approval.state), ["failed", "failed"]);
});

test("stop: runner retains the execution slot until aborted work settles", async () => {
  const started = deferred();
  const finish = deferred();
  const order = [];
  let activeSignal;
  const runner = createJobRunner({
    execute: async (job, { signal } = {}) => {
      order.push(job.tool);
      if (job.tool === "first") {
        activeSignal = signal;
        started.resolve();
        await finish.promise;
        throw new Error("late process error");
      }
      return "done";
    }
  });
  const first = runner.enqueue({ tool: "first" }).job;
  await started.promise;
  try {
    runner.stopAll();
    assert.equal(activeSignal.aborted, true);
    runner.enqueue({ tool: "after-stop" });
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(order, ["first"], "no overlap while the old process is shutting down");
  } finally {
    finish.resolve();
    await runner.drain();
  }
  assert.deepEqual(order, ["first", "after-stop"]);
  assert.equal(runner.get(first.id).error, "stopped by human");
  assert.equal(runner.list()[1].state, "completed");
  runner.stopAll();
  assert.equal(runner.list()[1].state, "completed", "completed work is not retroactively cancelled");
});

test("stop: MCP human adapter forwards authority and the agent cannot stop", async () => {
  const layer = createAgentLayer({ repoRoot: REPO_ROOT, env: {} });
  const message = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "brahma_stop", arguments: {} } };
  const human = await handleRpc(message, { role: "human", api: createAgentGateway({ agent: layer, role: "human" }) });
  assert.equal(human.result.isError, false, JSON.stringify(human.result.structuredContent));
  assert.equal(human.result.structuredContent.ok, true);
  const agent = await handleRpc(message, { role: "agent", api: createAgentGateway({ agent: layer, role: "agent" }) });
  assert.equal(agent.result.isError, true);
  assert.equal(agent.result.structuredContent.code, "unknown_tool");
  assert.throws(() => createAgentGateway({ agent: layer, role: "agent" }).stop(), { code: "human_role_required" });
});

async function waitFor(check, message, timeout = 2000) {
  const deadline = Date.now() + timeout;
  while (!check()) {
    if (Date.now() >= deadline) throw new Error(message);
    await delay(10);
  }
}

async function within(promise, ms) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("process did not settle after cancellation")), ms); })
    ]);
  } finally {
    clearTimeout(timer);
  }
}

test("executor: successful commands retain stdout and stderr", async () => {
  const result = await defaultExecFile(process.execPath, ["-e", "process.stdout.write('ready ✓');process.stderr.write('diagnostic');"]);
  assert.deepEqual(result, { stdout: "ready ✓", stderr: "diagnostic" });
});

test("executor: excessive output remains bounded", async () => {
  await assert.rejects(defaultExecFile(process.execPath, ["-e", "setInterval(()=>process.stdout.write('x'.repeat(4096)),1);"], {
    maxBuffer: 1024, timeout: 1000
  }), { code: "ERR_CHILD_PROCESS_STDIO_MAXBUFFER" });
});

for (const mode of ["abort", "timeout"]) {
  test(`executor: ${mode} terminates the renderer's spawned descendants`, { skip: process.platform === "win32" }, async (t) => {
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-process-stop-"));
    const parentFile = path.join(scratch, "parent.pid");
    const childFile = path.join(scratch, "child.pid");
    const heartbeat = path.join(scratch, "heartbeat");
    // The descendant deliberately ignores TERM. Group SIGKILL must end it too.
    const childCode = `const fs=require('node:fs');fs.writeFileSync(${JSON.stringify(childFile)},String(process.pid));process.on('SIGTERM',()=>{});setInterval(()=>fs.appendFileSync(${JSON.stringify(heartbeat)},'.'),10);`;
    const parentCode = `const fs=require('node:fs');fs.writeFileSync(${JSON.stringify(parentFile)},String(process.pid));require('node:child_process').spawn(process.execPath,['-e',${JSON.stringify(childCode)}],{stdio:['ignore','inherit','inherit']});setInterval(()=>{},1000);`;
    t.after(() => {
      for (const file of [childFile, parentFile]) {
        if (!fs.existsSync(file)) continue;
        const pid = Number(fs.readFileSync(file, "utf8"));
        try { process.kill(pid, "SIGKILL"); } catch (_) {}
      }
      fs.rmSync(scratch, { recursive: true, force: true });
    });
    const controller = new AbortController();
    const execution = defaultExecFile(process.execPath, ["-e", parentCode], {
      signal: controller.signal, timeout: mode === "timeout" ? 750 : 10000
    });
    // Attach the rejection handler before a timer or AbortSignal can fire.
    const settled = execution.then(() => ({ ok: true }), (error) => ({ ok: false, error }));
    await waitFor(() => fs.existsSync(heartbeat), "descendant did not start");
    if (mode === "abort") controller.abort(new Error("stopped by human"));
    const result = await within(settled, 2000);
    assert.equal(result.ok, false);
    if (mode === "abort") assert.equal(result.error.name, "AbortError");
    const size = fs.statSync(heartbeat).size;
    await delay(80);
    assert.equal(fs.statSync(heartbeat).size, size, "descendant remained alive after its renderer stopped");
  });
}

test("executor: the renderer wrapper keeps sclang and its children cancellable", { skip: process.platform === "win32" }, async (t) => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-wrapper-stop-"));
  const bin = path.join(scratch, "bin");
  fs.mkdirSync(bin);
  const parentFile = path.join(scratch, "sclang.pid");
  const childFile = path.join(scratch, "synth.pid");
  const heartbeat = path.join(scratch, "heartbeat");
  const childCode = `const fs=require('node:fs');fs.writeFileSync(${JSON.stringify(childFile)},String(process.pid));setInterval(()=>fs.appendFileSync(${JSON.stringify(heartbeat)},'.'),10);`;
  const parentCode = `const fs=require('node:fs');fs.writeFileSync(${JSON.stringify(parentFile)},String(process.pid));require('node:child_process').spawn(process.execPath,['-e',${JSON.stringify(childCode)}],{stdio:['ignore','inherit','inherit']});setInterval(()=>{},1000);`;
  fs.writeFileSync(path.join(bin, "sclang"), `#!/usr/bin/env node\n${parentCode}\n`, { mode: 0o700 });
  fs.writeFileSync(path.join(bin, "scsynth"), "#!/bin/sh\nexit 0\n", { mode: 0o700 });
  t.after(() => {
    for (const file of [childFile, parentFile]) {
      if (!fs.existsSync(file)) continue;
      try { process.kill(Number(fs.readFileSync(file, "utf8")), "SIGKILL"); } catch (_) {}
    }
    fs.rmSync(scratch, { recursive: true, force: true });
  });
  const controller = new AbortController();
  const tools = createTools({
    repoRoot: REPO_ROOT, scratchRoot: scratch,
    execFile: (file, args, options) => defaultExecFile(file, args, {
      ...options, timeout: 10000,
      env: { ...options.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`, TMPDIR: scratch }
    })
  });
  const execution = tools.run("render_pattern", { events: EVENTS, duration: 1 }, { signal: controller.signal });
  const settled = execution.then(() => ({ ok: true }), (error) => ({ ok: false, error }));
  await waitFor(() => fs.existsSync(heartbeat), "renderer fixture did not start");
  controller.abort(new Error("stopped by human"));
  const result = await within(settled, 2000);
  assert.equal(result.ok, false);
  assert.equal(result.error.name, "AbortError");
  const size = fs.statSync(heartbeat).size;
  await delay(80);
  assert.equal(fs.statSync(heartbeat).size, size, "the renderer's timeout wrapper detached its child from cancellation");
});
