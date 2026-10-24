"use strict";
/**
 * client.js — the two gateways behind one tool surface.
 *
 * The MCP server never talks to the approval store directly. It talks to a small
 * client with six methods, and there are two implementations of that client:
 *
 *   createHttpGateway   used by the stdio bridge: HTTP to a running gateway,
 *                       authenticated as `agent` (Bearer) or `human` (cookie).
 *   createAgentGateway  used by the in-process `/mcp` mount: calls the agent layer
 *                       in the same process, after the HTTP layer has already
 *                       resolved the caller's role.
 *
 * Both reject with GatewayError carrying the gateway's typed code, so a tool result
 * looks the same whether the caller arrived over stdio or over HTTP.
 */

const fs = require("node:fs");
const path = require("node:path");

class GatewayError extends Error {
  constructor(message, { status = 0, code = "gateway_error", detail = null } = {}) {
    super(message);
    this.name = "GatewayError";
    this.status = status;
    this.code = code;
    this.detail = detail;
  }
}

/** Turn the gateway's {ok:false, code, message} into a rejection. */
function unwrap(body, status = 200) {
  if (body && body.ok === false) {
    throw new GatewayError(body.message || body.code || "gateway refused", {
      status,
      code: body.code || "gateway_error",
      detail: body
    });
  }
  return body;
}

function createHttpGateway({ baseUrl, token, role = "agent", timeoutMs = 15000, fetchImpl = fetch } = {}) {
  if (!baseUrl) throw new Error("createHttpGateway requires baseUrl");
  if (!token) throw new Error("createHttpGateway requires a token");
  if (role !== "agent" && role !== "human") throw new Error(`unknown role: ${role}`);

  const root = String(baseUrl).replace(/\/+$/, "");

  function headers() {
    const h = { "content-type": "application/json" };
    if (role === "human") h.cookie = `brahma_human=${token}`;
    else h.authorization = `Bearer ${token}`;
    return h;
  }

  async function request(method, pathname, body) {
    let res;
    try {
      res = await fetchImpl(`${root}${pathname}`, {
        method,
        headers: headers(),
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs)
      });
    } catch (err) {
      throw new GatewayError(`gateway unreachable at ${root}: ${err.message}`, {
        code: err.name === "TimeoutError" ? "gateway_timeout" : "gateway_unreachable"
      });
    }

    const text = await res.text();
    let parsed = null;
    if (text) {
      try { parsed = JSON.parse(text); } catch (_) { /* non-JSON error page */ }
    }

    if (!res.ok) {
      const code = parsed && parsed.code ? parsed.code : `http_${res.status}`;
      const message = parsed && (parsed.message || parsed.error)
        ? (parsed.message || parsed.error)
        : text.slice(0, 300) || `HTTP ${res.status}`;
      throw new GatewayError(message, { status: res.status, code, detail: parsed });
    }
    return parsed;
  }

  const idPath = (id, suffix) => `/api/agent/approvals/${encodeURIComponent(id)}${suffix}`;

  return {
    role,
    providers: () => request("GET", "/api/agent/providers"),
    propose: async (args) => unwrap(await request("POST", "/api/agent/propose", args)),
    approvals: () => request("GET", "/api/agent/approvals"),
    job: (id) => request("GET", `/api/agent/jobs/${encodeURIComponent(id)}`),
    accept: async (id) => unwrap(await request("POST", idPath(id, "/accept"), {})),
    reject: async (id, reason) => unwrap(await request("POST", idPath(id, "/reject"), { reason: reason || "" })),
    run: async (id) => unwrap(await request("POST", idPath(id, "/run"), {})),
    engine: () => request("GET", "/api/runtimes")
  };
}

/**
 * In-process adapter for the `/mcp` mount.
 *
 * `role` is not decoration: accept/reject/run re-check it here, so a future route
 * that forgot the HTTP guard still cannot promote a proposal with an agent role.
 */
function createAgentGateway({ agent, role = "agent", engine } = {}) {
  if (!agent) throw new Error("createAgentGateway requires the agent layer");
  if (role !== "agent" && role !== "human") throw new Error(`unknown role: ${role}`);

  function humanOnly(action, fn) {
    if (role !== "human") {
      throw new GatewayError(`${action} requires the human role`, { status: 403, code: "human_role_required" });
    }
    return fn();
  }

  return {
    role,
    async providers() {
      return { providers: agent.available(), tools: agent.toolset() };
    },
    async propose(args = {}) {
      return unwrap(await agent.propose({ ...args, proposedBy: role === "human" ? "human" : "agent" }));
    },
    async approvals() {
      return { approvals: agent.approvals.list() };
    },
    async job(id) {
      const job = agent.runner.get(id);
      if (!job) throw new GatewayError(`No job ${id}`, { status: 404, code: "unknown_job" });
      return { job };
    },
    accept: (id) => humanOnly("accept", async () => unwrap(await agent.accept(id, { actor: "human" }))),
    reject: (id, reason) => humanOnly("reject", async () => unwrap(await agent.reject(id, { actor: "human", reason }))),
    run: (id) => humanOnly("run", async () => unwrap(await agent.run(id, { actor: "human" }))),
    engine: () => (typeof engine === "function" ? engine() : { sandbox: null, runtimes: [] })
  };
}

/**
 * Resolve the token for a stdio bridge.
 *
 * The human token is never written to disk. The agent token is: the gateway writes
 * it to `.runtime/agent-token` (0600) at boot so a client can start without the
 * operator pasting a secret into three different config files.
 */
function resolveToken({ role = "agent", env = process.env, tokenFile, port = 3000 } = {}) {
  const clean = (v) => (typeof v === "string" && v.trim() ? v.trim() : null);

  if (role === "human") {
    const direct = clean(env.BRAHMA_HUMAN_TOKEN);
    if (direct) return direct;
    const file = tokenFile || env.BRAHMA_HUMAN_TOKEN_FILE;
    if (!file) return null;
    try { return clean(fs.readFileSync(file, "utf8")); } catch (_) { return null; }
  }

  const direct = clean(env.BRAHMA_AGENT_TOKEN);
  if (direct) return direct;

  // One file per gateway port, so a smoke run on 3939 cannot rotate the token a
  // workbench MCP bridge on 3000 is using.
  const file = tokenFile || env.BRAHMA_AGENT_TOKEN_FILE || path.join(__dirname, "..", "..", ".runtime", `agent-token-${port}`);
  try { return clean(fs.readFileSync(file, "utf8")); } catch (_) { return null; }
}

/** Write the per-launch agent token where local MCP bridges can find it. */
function writeAgentTokenFile(dir, token, port = 3000) {
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  try { fs.chmodSync(dir, 0o700); } catch (_) { /* best effort on shared filesystems */ }
  const file = path.join(dir, `agent-token-${port}`);
  fs.writeFileSync(file, `${token}\n`, { mode: 0o600 });
  try { fs.chmodSync(file, 0o600); } catch (_) { /* best effort */ }
  return file;
}

module.exports = {
  GatewayError,
  unwrap,
  createHttpGateway,
  createAgentGateway,
  resolveToken,
  writeAgentTokenFile
};
