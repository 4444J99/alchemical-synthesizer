"use strict";

/**
 * agent-http.test.js — the role gates on /api/agent/*, over real HTTP.
 *
 * The unit tests prove the state machine. This file proves the gateway cannot be
 * talked into skipping it: an agent token can propose, and the same token gets a
 * 403 on accept and run. Nothing here renders — the successful run path is covered
 * by the injected-exec test in agent.test.js, and by a real render observed through
 * forge/render-pattern.sh.
 */

const test = require("node:test");
const assert = require("node:assert/strict");

process.env.PORT = "0";
process.env.HOST = "127.0.0.1";
process.env.BRAHMA_OSC_LISTEN_PORT = "0";
process.env.BRAHMA_OSC_SEND_PORT = "57998";
process.env.BRAHMA_DIRT_PORT = "57134";
process.env.BRAHMA_AGENT_TOKEN = "test-agent-token-agent-http-0001"; // allow-secret
process.env.BRAHMA_HUMAN_TOKEN = "test-human-token-agent-http-0001"; // allow-secret

const { server, closeServer } = require("../server");

const AGENT_TOKEN = process.env.BRAHMA_AGENT_TOKEN;
const HUMAN_TOKEN = process.env.BRAHMA_HUMAN_TOKEN;

test.after(async () => {
  await new Promise((resolve) => closeServer(resolve));
});

function port() {
  return server.address().port;
}

function agentHeaders() {
  return {
    "content-type": "application/json",
    origin: `http://127.0.0.1:${port()}`,
    authorization: `Bearer ${AGENT_TOKEN}`
  };
}

function humanHeaders() {
  return {
    "content-type": "application/json",
    origin: `http://127.0.0.1:${port()}`,
    cookie: `brahma_human=${HUMAN_TOKEN}`
  };
}

test("agent HTTP: unauthenticated callers are refused", async () => {
  const res = await fetch(`http://127.0.0.1:${port()}/api/agent/providers`, {
    headers: { origin: `http://127.0.0.1:${port()}` }
  });
  assert.equal(res.status, 401);
  assert.equal((await res.json()).code, "auth_required");
});

test("agent HTTP: providers report honest availability", async () => {
  const res = await fetch(`http://127.0.0.1:${port()}/api/agent/providers`, { headers: agentHeaders() });
  assert.equal(res.status, 200);

  const body = await res.json();
  const byName = Object.fromEntries(body.providers.map((p) => [p.name, p]));

  assert.equal(byName.mock.available, true);
  assert.equal(byName.claude.available, false, "this host has no ANTHROPIC_API_KEY");
  assert.match(byName.tidal.reason, /not_installed/);
  assert.match(byName.sonicpi.reason, /not_installed/);

  const tool = body.tools.find((t) => t.name === "render_pattern");
  assert.equal(tool.approval, "required");
});

test("agent HTTP: an agent may propose, and the proposal does not run", async () => {
  const res = await fetch(`http://127.0.0.1:${port()}/api/agent/propose`, {
    method: "POST",
    headers: agentHeaders(),
    body: JSON.stringify({ provider: "mock", prompt: "a slow chord" })
  });
  assert.equal(res.status, 200);

  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.approval.state, "proposed");
  assert.equal(body.approval.proposedBy, "agent");
  assert.ok(body.events.length > 0);

  const jobs = await fetch(`http://127.0.0.1:${port()}/api/agent/approvals`, { headers: agentHeaders() });
  const listed = await jobs.json();
  assert.equal(listed.approvals.some((a) => a.id === body.approval.id && a.state === "proposed"), true);
});

test("agent HTTP: an agent cannot accept its own proposal", async () => {
  const proposed = await fetch(`http://127.0.0.1:${port()}/api/agent/propose`, {
    method: "POST",
    headers: agentHeaders(),
    body: JSON.stringify({ provider: "mock", prompt: "gated" })
  }).then((r) => r.json());

  const res = await fetch(
    `http://127.0.0.1:${port()}/api/agent/approvals/${proposed.approval.id}/accept`,
    { method: "POST", headers: agentHeaders(), body: "{}" }
  );
  assert.equal(res.status, 403);
  assert.equal((await res.json()).code, "human_role_required");
});

test("agent HTTP: an agent cannot run an accepted proposal", async () => {
  const proposed = await fetch(`http://127.0.0.1:${port()}/api/agent/propose`, {
    method: "POST",
    headers: agentHeaders(),
    body: JSON.stringify({ provider: "mock", prompt: "run gate" })
  }).then((r) => r.json());

  const accepted = await fetch(
    `http://127.0.0.1:${port()}/api/agent/approvals/${proposed.approval.id}/accept`,
    { method: "POST", headers: humanHeaders(), body: "{}" }
  );
  assert.equal(accepted.status, 200);

  const res = await fetch(
    `http://127.0.0.1:${port()}/api/agent/approvals/${proposed.approval.id}/run`,
    { method: "POST", headers: agentHeaders(), body: "{}" }
  );
  assert.equal(res.status, 403);
  assert.equal((await res.json()).code, "human_role_required");
});

test("agent HTTP: a human accepts, and a rejected proposal cannot run", async () => {
  const proposed = await fetch(`http://127.0.0.1:${port()}/api/agent/propose`, {
    method: "POST",
    headers: agentHeaders(),
    body: JSON.stringify({ provider: "mock", prompt: "throw this away" })
  }).then((r) => r.json());

  const rejected = await fetch(
    `http://127.0.0.1:${port()}/api/agent/approvals/${proposed.approval.id}/reject`,
    { method: "POST", headers: humanHeaders(), body: JSON.stringify({ reason: "not now" }) }
  );
  assert.equal(rejected.status, 200);
  assert.equal((await rejected.json()).approval.state, "rejected");

  const run = await fetch(
    `http://127.0.0.1:${port()}/api/agent/approvals/${proposed.approval.id}/run`,
    { method: "POST", headers: humanHeaders(), body: "{}" }
  );
  assert.equal(run.status, 409);
  assert.equal((await run.json()).code, "not_accepted");
});

test("agent HTTP: unknown approvals and jobs are 404, not 500", async () => {
  const accept = await fetch(`http://127.0.0.1:${port()}/api/agent/approvals/apv_nope/accept`, {
    method: "POST",
    headers: humanHeaders(),
    body: "{}"
  });
  assert.equal(accept.status, 404);

  const job = await fetch(`http://127.0.0.1:${port()}/api/agent/jobs/job_nope`, { headers: agentHeaders() });
  assert.equal(job.status, 404);
});

test("agent HTTP: an unavailable provider is a typed refusal, not an empty proposal", async () => {
  const res = await fetch(`http://127.0.0.1:${port()}/api/agent/propose`, {
    method: "POST",
    headers: agentHeaders(),
    body: JSON.stringify({ provider: "tidal", prompt: "x" })
  });
  assert.equal(res.status, 400);

  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.code, "provider_unavailable");
  assert.match(body.message, /not_installed/);
  assert.equal(body.events, undefined);
});

test("agent HTTP: a cross-origin proposal is refused even with a valid token", async () => {
  const res = await fetch(`http://127.0.0.1:${port()}/api/agent/propose`, {
    method: "POST",
    headers: { ...agentHeaders(), origin: "https://evil.example" },
    body: JSON.stringify({ provider: "mock", prompt: "x" })
  });
  assert.equal(res.status, 403);
  assert.equal((await res.json()).code, "forbidden_origin");
});
