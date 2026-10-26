"use strict";

/**
 * mcp.test.js — the agent transports, over both wires.
 *
 * The HTTP tests prove the role-scoped tool lists and the in-process gateway. The
 * stdio test spawns the exact binary the four clients launch, so "Claude/Codex/
 * OpenCode/agy can reach the loop" is a tested claim rather than a documented one.
 *
 * Nothing here renders: propose/accept/reject are covered, run is only tested for
 * its refusal path. The real render is observed through forge/render-pattern.sh.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

const runtimeDir = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-mcp-test-"));

process.env.PORT = "0";
process.env.HOST = "127.0.0.1";
process.env.BRAHMA_OSC_LISTEN_PORT = "0";
process.env.BRAHMA_OSC_SEND_PORT = "57997";
process.env.BRAHMA_DIRT_PORT = "57135";
process.env.BRAHMA_RUNTIME_DIR = runtimeDir;
process.env.BRAHMA_AGENT_TOKEN = "test-agent-token-mcp-0001"; // allow-secret
process.env.BRAHMA_HUMAN_TOKEN = "test-human-token-mcp-0001"; // allow-secret

const { server, closeServer } = require("../server");

const AGENT_TOKEN = process.env.BRAHMA_AGENT_TOKEN;
const HUMAN_TOKEN = process.env.BRAHMA_HUMAN_TOKEN;

test.after(async () => {
  await new Promise((resolve) => closeServer(resolve));
  fs.rmSync(runtimeDir, { recursive: true, force: true });
});

function port() { return server.address().port; }
function base() { return `http://127.0.0.1:${port()}`; }

function listening() {
  if (server.listening) return Promise.resolve();
  return new Promise((resolve) => server.once("listening", resolve));
}

function agentHeaders() {
  return { "content-type": "application/json", authorization: `Bearer ${AGENT_TOKEN}` };
}

function humanHeaders() {
  return { "content-type": "application/json", cookie: `brahma_human=${HUMAN_TOKEN}` };
}

async function rpc(headers, message) {
  const res = await fetch(`${base()}/mcp`, {
    method: "POST",
    headers,
    body: JSON.stringify(message)
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

function call(headers, name, args) {
  return rpc(headers, {
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: { name, arguments: args || {} }
  });
}

async function propose(prompt) {
  const out = await call(agentHeaders(), "brahma_propose_pattern", { provider: "mock", prompt });
  const body = out.body.result;
  assert.equal(body.isError, false, JSON.stringify(body.structuredContent));
  return body.structuredContent.approval;
}

test("mcp: the gateway writes the agent token 0600 and never the human token", async () => {
  await listening();
  const file = path.join(runtimeDir, `agent-token-${port()}`);

  for (let i = 0; i < 40 && !fs.existsSync(file); i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.ok(fs.existsSync(file), `token file not written at ${file}`);

  assert.equal(fs.readFileSync(file, "utf8").trim(), AGENT_TOKEN);
  assert.equal(fs.statSync(file).mode & 0o777, 0o600);

  for (const name of fs.readdirSync(runtimeDir)) {
    assert.doesNotMatch(
      fs.readFileSync(path.join(runtimeDir, name), "utf8"),
      new RegExp(HUMAN_TOKEN),
      `${name} must not contain the human token`
    );
  }
});

test("mcp HTTP: unauthenticated initialize is refused", async () => {
  const out = await rpc({ "content-type": "application/json" }, {
    jsonrpc: "2.0", id: 1, method: "initialize", params: {}
  });
  assert.equal(out.status, 401);
  assert.equal(out.body.error.code, -32001);
});

test("mcp HTTP: the agent tool list offers propose and no decision tools", async () => {
  const out = await rpc(agentHeaders(), { jsonrpc: "2.0", id: 1, method: "tools/list" });
  assert.equal(out.status, 200);

  const names = out.body.result.tools.map((t) => t.name);
  for (const expected of ["brahma_provider_status", "brahma_propose_pattern", "brahma_approvals", "brahma_job", "brahma_engine_status"]) {
    assert.ok(names.includes(expected), `missing ${expected}`);
  }
  for (const forbidden of ["brahma_accept", "brahma_reject", "brahma_run", "brahma_stop"]) {
    assert.equal(names.includes(forbidden), false, `${forbidden} must not be exposed to an agent`);
  }
});

test("mcp HTTP: an agent cannot call a decision tool by guessing its name", async () => {
  const out = await call(agentHeaders(), "brahma_accept", { approvalId: "apv_guess" });
  const body = out.body.result;
  assert.equal(body.isError, true);
  assert.equal(body.structuredContent.code, "unknown_tool");
});

test("mcp HTTP: propose files an approval and does not run", async () => {
  const approval = await propose("an mcp chord");
  assert.equal(approval.state, "proposed");
  assert.equal(approval.proposedBy, "agent");

  const list = await call(agentHeaders(), "brahma_approvals", { state: "proposed" });
  const ids = list.body.result.structuredContent.approvals.map((a) => a.id);
  assert.ok(ids.includes(approval.id));
});

test("mcp HTTP: the human tool list adds accept/reject/run", async () => {
  const out = await rpc(humanHeaders(), { jsonrpc: "2.0", id: 1, method: "tools/list" });
  const names = out.body.result.tools.map((t) => t.name);
  for (const expected of ["brahma_accept", "brahma_reject", "brahma_run", "brahma_stop", "brahma_propose_pattern"]) {
    assert.ok(names.includes(expected), `missing ${expected}`);
  }
});

test("mcp HTTP: human stop succeeds and agent stop is not exposed", async () => {
  const human = await call(humanHeaders(), "brahma_stop");
  assert.equal(human.body.result.isError, false);
  assert.equal(human.body.result.structuredContent.ok, true);
  const agent = await call(agentHeaders(), "brahma_stop");
  assert.equal(agent.body.result.isError, true);
  assert.equal(agent.body.result.structuredContent.code, "unknown_tool");
});

test("mcp HTTP: accepting is a separate act from running", async () => {
  const approval = await propose("accept without run");

  const accepted = await call(humanHeaders(), "brahma_accept", { approvalId: approval.id });
  assert.equal(accepted.body.result.isError, false);
  assert.equal(accepted.body.result.structuredContent.approval.state, "accepted");

  // Still no job: accept must not have queued anything.
  const list = await call(agentHeaders(), "brahma_approvals", { state: "accepted" });
  const record = list.body.result.structuredContent.approvals.find((a) => a.id === approval.id);
  assert.ok(record);
  assert.equal(record.runner, null);
});

test("mcp HTTP: run refuses an unaccepted proposal, and an unknown job is typed", async () => {
  const approval = await propose("run without accept");

  const run = await call(humanHeaders(), "brahma_run", { approvalId: approval.id });
  assert.equal(run.body.result.isError, true);
  assert.equal(run.body.result.structuredContent.code, "not_accepted");

  const job = await call(agentHeaders(), "brahma_job", { jobId: "job_nope" });
  assert.equal(job.body.result.isError, true);
  assert.equal(job.body.result.structuredContent.code, "unknown_job");
});

test("mcp HTTP: engine status answers with the shared runtime snapshot", async () => {
  const out = await call(agentHeaders(), "brahma_engine_status");
  const body = out.body.result.structuredContent;
  assert.equal(typeof body.sandbox, "object");
  assert.equal(typeof body.runtimes, "object");
  assert.equal(body.runtimes.strudel.name, "Strudel");
});

function runStdio(lines, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(__dirname, "..", "bin", "brahma-mcp.js")], {
      env: { ...process.env, ...env },
      stdio: ["pipe", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error(`stdio bridge timed out; stderr: ${stderr}`));
    }, 10000);

    child.stdout.on("data", (d) => { stdout += d; });
    child.stderr.on("data", (d) => { stderr += d; });
    child.on("error", (err) => { clearTimeout(timer); reject(err); });
    child.on("exit", (code) => { clearTimeout(timer); resolve({ code, stdout, stderr }); });
    child.stdin.end(lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  });
}

test("mcp stdio: the bridge every client launches answers initialize and tools/list", async () => {
  const { code, stdout, stderr } = await runStdio(
    [
      { jsonrpc: "2.0", id: 1, method: "initialize", params: {} },
      { jsonrpc: "2.0", id: 2, method: "tools/list" }
    ],
    {
      BRAHMA_MCP_ROLE: "agent",
      BRAHMA_GATEWAY_URL: base(),
      BRAHMA_AGENT_TOKEN: AGENT_TOKEN
    }
  );

  assert.equal(code, 0, stderr);
  const responses = stdout.trim().split("\n").map((line) => JSON.parse(line));
  assert.equal(responses.length, 2);

  assert.equal(responses[0].result.serverInfo.name, "brahma-workbench");
  assert.match(responses[0].result.instructions, /Role: agent/);
  assert.match(responses[0].result.instructions, /Measured/);

  const names = responses[1].result.tools.map((t) => t.name);
  assert.ok(names.includes("brahma_propose_pattern"));
  assert.equal(names.includes("brahma_run"), false);
});

test("mcp stdio: the human role refuses to start without a human token", async () => {
  const { code, stderr } = await runStdio(
    [{ jsonrpc: "2.0", id: 1, method: "ping" }],
    {
      BRAHMA_MCP_ROLE: "human",
      BRAHMA_GATEWAY_URL: base(),
      BRAHMA_HUMAN_TOKEN: "",
      BRAHMA_HUMAN_TOKEN_FILE: ""
    }
  );

  assert.equal(code, 2);
  assert.match(stderr, /no human token/);
});
