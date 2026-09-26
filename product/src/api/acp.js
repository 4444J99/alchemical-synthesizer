"use strict";
/**
 * acp.js — ACP adapters (both meanings of the acronym), one core.
 *
 *  1. Agent Communication Protocol (REST, BeeAI-style):
 *        GET  /acp/agents
 *        POST /acp/runs            { agent_name, input:[messages] } -> run
 *        GET  /acp/runs/:id
 *     For agent-to-agent interop across the ORGANVM ecosystem.
 *
 *  2. Agent Client Protocol (JSON-RPC, Zed-style):
 *        POST /acp/jsonrpc         methods: initialize, session/new, session/prompt
 *     Also exposed over stdio via bin/acp-stdio.js for native ACP clients.
 *
 * Both translate agent prompts into capability-core invocations (actions.js),
 * metering any costed action against the caller's API key.
 */

const express = require("express");
const crypto = require("crypto");
const actions = require("../core/actions");
const { chargeKey, extractKey } = require("../auth/metering");
const { collection } = require("../core/store");

const router = express.Router();
router.use(express.json({ limit: "256kb" }));

const AGENT = {
  name: "brahma",
  description: "The Alchemical Synthesizer agent — lists modules, reports organism state, and renders specimens.",
  metadata: { framework: "brahma-foundry", capabilities: actions.listActions().map((a) => a.name) }
};

const runs = new Map(); // ephemeral run store (id -> run)

/**
 * Interpret an agent prompt into an action invocation.
 * Accepts either a structured directive {action, args} embedded in the text,
 * or a small natural-language command grammar.
 */
function interpret(text) {
  const raw = String(text || "").trim();
  // Structured form: {"action":"render_specimen","args":{...}}
  try {
    const obj = JSON.parse(raw);
    if (obj && obj.action) return { action: obj.action, args: obj.args || {} };
  } catch (_) { /* not JSON, fall through */ }

  const lower = raw.toLowerCase();
  const lines = lower.split(/[\n\r\u2028\u2029]/);
  // Find the first command once, then scan its suffix once. Repeated command
  // words must not cause a fresh scan of the remaining prompt at every offset.
  const afterWord = (line, command, target) => {
    const match = command.exec(line);
    return match ? target.exec(line.slice(match.index + match[0].length)) : null;
  };
  if (/\b(state|status|telemetry|organism)\b/.test(lower)) return { action: "get_organism_state", args: {} };
  if (lines.some((line) => afterWord(line, /\blist\b/, /\b(specimen|marketplace)\b/))) return { action: "list_specimens", args: {} };
  if (lines.some((line) => afterWord(line, /\b(list|show|catalog)\b/, /\bmodule/))) return { action: "list_modules", args: {} };
  // "render from <module>" / "render of <module>" / "render <module>"
  let render = null;
  let seenRender = false, previousEnd = 0;
  const words = /\b(render|from|of|with)\b/g;
  const moduleSuffix = /\s+(?:the\s+)?([a-z0-9]+)/y;
  for (const word of lower.matchAll(words)) {
    if (/[\n\r\u2028\u2029]/.test(lower.slice(previousEnd, word.index))) seenRender = false;
    previousEnd = word.index + word[0].length;
    if (word[1] === "render") { seenRender = true; continue; }
    if (!seenRender) continue;
    moduleSuffix.lastIndex = previousEnd;
    render = moduleSuffix.exec(lower);
    // A connector may continue onto the next line, but a fresh command may not
    // be consumed as its module name. Let the scanner parse that command.
    if (render && render[1] === "render" && /[\n\r\u2028\u2029]/.test(render[0])) {
      render = null;
      continue;
    }
    if (render) break;
  }
  if (!render) render = lower.match(/\brender\b\s+(?:a\s+specimen\s+)?(?:the\s+)?([a-z0-9]+)/);
  if (render) {
    // Title-case the captured module token to match catalog naming.
    const tok = render[1];
    const mod = tok.charAt(0).toUpperCase() + tok.slice(1);
    return { action: "render_specimen", args: { module: mod } };
  }
  if (/\bmodule\b/.test(lower)) {
    let offset = 0;
    for (const line of lines) {
      const last = line.lastIndexOf("module");
      if (last >= 0) {
        const end = offset + last + (line[last + 6] === "s" ? 7 : 6);
        return { action: "list_modules", args: { q: (lower.slice(0, offset) + lower.slice(end)).trim() } };
      }
      offset += line.length + 1;
    }
  }
  // Default: list modules.
  return { action: "list_modules", args: {} };
}

/** Execute an interpreted directive with metering. */
function execute(directive, apiKey) {
  const action = actions.getAction(directive.action);
  if (!action) return { ok: false, error: `unknown action: ${directive.action}` };
  if (action.cost > 0) {
    if (!apiKey) return { ok: false, error: "missing_api_key", status: 401 };
    const charge = chargeKey(apiKey, action.cost);
    if (!charge.ok) return { ok: false, error: charge.error, status: charge.status || 402, detail: charge };
  }
  try {
    return { ok: true, output: action.handler(directive.args) };
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

function promptTextFrom(input) {
  // ACP messages: input is an array of messages, each with parts[].content
  if (typeof input === "string") return input;
  if (Array.isArray(input)) {
    const parts = [];
    for (const m of input) {
      const ps = m.parts || m.content || [];
      if (typeof ps === "string") { parts.push(ps); continue; }
      for (const p of (Array.isArray(ps) ? ps : [ps])) {
        if (typeof p === "string") parts.push(p);
        else if (p && p.content) parts.push(p.content);
        else if (p && p.text) parts.push(p.text);
      }
    }
    return parts.join("\n");
  }
  return "";
}

function messageOut(text) {
  return { role: "agent/brahma", parts: [{ content_type: "application/json", content: text }] };
}

// ========== Agent Communication Protocol (REST) ==========

router.get("/agents", (req, res) => res.json({ agents: [AGENT] }));
router.get("/agents/:name", (req, res) =>
  req.params.name === AGENT.name ? res.json(AGENT) : res.status(404).json({ error: "agent_not_found" }));

router.post("/runs", (req, res) => {
  const body = req.body || {};
  const agentName = body.agent_name || body.agent || "brahma";
  if (agentName !== "brahma") return res.status(404).json({ error: "agent_not_found" });

  const text = promptTextFrom(body.input);
  const directive = interpret(text);
  const result = execute(directive, extractKey(req));

  const run = {
    run_id: "run_" + crypto.randomBytes(8).toString("hex"),
    agent_name: "brahma",
    status: result.ok ? "completed" : "failed",
    directive,
    output: result.ok
      ? [messageOut(JSON.stringify(result.output, null, 2))]
      : [messageOut(JSON.stringify({ error: result.error, detail: result.detail }, null, 2))],
    error: result.ok ? null : { message: result.error },
    created_at: new Date().toISOString()
  };
  runs.set(run.run_id, run);
  // Lightweight persistence of agent activity for the dashboard.
  try { collection("events").insert({ ts: run.created_at, type: "acp.run", ref: `${directive.action}:${run.status}` }); } catch (_) {}
  return res.status(result.ok ? 200 : 200).json(run);
});

router.get("/runs/:id", (req, res) => {
  const run = runs.get(req.params.id);
  return run ? res.json(run) : res.status(404).json({ error: "run_not_found" });
});

// ========== Agent Client Protocol (JSON-RPC over HTTP) ==========

const sessions = new Map();

function acpRpc(msg, req) {
  if (!msg || msg.jsonrpc !== "2.0") return { jsonrpc: "2.0", id: null, error: { code: -32600, message: "Invalid Request" } };
  const { id, method, params } = msg;
  switch (method) {
    case "initialize":
      return { jsonrpc: "2.0", id, result: {
        protocolVersion: 1,
        agentCapabilities: { promptCapabilities: { embeddedContext: true } },
        serverInfo: { name: "brahma", version: "0.1.0" }
      } };
    case "session/new": {
      const sid = "sess_" + crypto.randomBytes(8).toString("hex");
      sessions.set(sid, { createdAt: Date.now() });
      return { jsonrpc: "2.0", id, result: { sessionId: sid } };
    }
    case "session/prompt": {
      const text = promptTextFrom((params && params.prompt) || (params && params.input) || "");
      const directive = interpret(text);
      const result = execute(directive, extractKey(req));
      return { jsonrpc: "2.0", id, result: {
        stopReason: result.ok ? "end_turn" : "refusal",
        content: [{ type: "text", text: result.ok ? JSON.stringify(result.output, null, 2) : `Error: ${result.error}` }],
        directive
      } };
    }
    default:
      return { jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } };
  }
}

router.get("/jsonrpc", (req, res) => res.json({
  protocol: "agent-client-protocol", transport: "http-jsonrpc + stdio",
  methods: ["initialize", "session/new", "session/prompt"], stdio: "node bin/acp-stdio.js"
}));

router.post("/jsonrpc", (req, res) => {
  const body = req.body;
  if (Array.isArray(body)) return res.json(body.map((m) => acpRpc(m, req)));
  return res.json(acpRpc(body, req));
});

router.get("/", (req, res) => res.json({
  service: "brahma-foundry-acp",
  agent_communication_protocol: { agents: "/acp/agents", runs: "/acp/runs" },
  agent_client_protocol: { jsonrpc: "/acp/jsonrpc", stdio: "node bin/acp-stdio.js" }
}));

// Export interpret/execute so the stdio adapter reuses the exact same core.
module.exports = router;
module.exports.interpret = interpret;
module.exports.execute = execute;
module.exports.acpRpc = acpRpc;
module.exports.promptTextFrom = promptTextFrom;
