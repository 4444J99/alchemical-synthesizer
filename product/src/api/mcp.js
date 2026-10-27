"use strict";
/**
 * mcp.js — Model Context Protocol server (Streamable HTTP / JSON-RPC 2.0).
 *
 * Exposes the capability core (actions.js) as MCP tools so any MCP client
 * (Claude, IDE agents, etc.) can drive the Brahma engine. Tool calls that have
 * a cost are metered against the caller's API key — the agent surface is a
 * billable product, not a free-for-all.
 *
 * Endpoint: POST /mcp   (JSON-RPC; supports single + batched requests)
 *           GET  /mcp   (capability descriptor for discovery)
 */

const express = require("express");
const actions = require("../core/actions");
const { chargeKey, extractKey } = require("../auth/metering");

const router = express.Router();
router.use(express.json({ limit: "256kb" }));

const PROTOCOL_VERSION = "2025-06-18";
const SERVER_INFO = { name: "brahma-foundry", version: "0.1.0" };

function rpcResult(id, result) { return { jsonrpc: "2.0", id, result }; }
function rpcError(id, code, message, data) { return { jsonrpc: "2.0", id, error: { code, message, ...(data ? { data } : {}) } }; }

function handleOne(msg, req) {
  if (!msg || msg.jsonrpc !== "2.0" || !msg.method) {
    return rpcError(msg && msg.id != null ? msg.id : null, -32600, "Invalid Request");
  }
  const { id, method, params } = msg;

  switch (method) {
    case "initialize":
      return rpcResult(id, {
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: SERVER_INFO,
        capabilities: { tools: { listChanged: false } },
        instructions: "Brahma Foundry — drive the Alchemical Synthesizer. Tool calls with cost>0 require a metered API key (Authorization: Bearer)."
      });

    case "notifications/initialized":
      return null; // notification, no response

    case "ping":
      return rpcResult(id, {});

    case "tools/list":
      return rpcResult(id, {
        tools: actions.listActions().map((a) => ({
          name: a.name, description: a.description + (a.cost ? `  [cost: ${a.cost}]` : ""), inputSchema: a.inputSchema
        }))
      });

    case "tools/call": {
      const name = params && params.name;
      const args = (params && params.arguments) || {};
      const action = actions.getAction(name);
      if (!action) return rpcError(id, -32602, `Unknown tool: ${name}`);

      // Meter cost against the API key.
      let auth = {};
      if (action.cost > 0) {
        const key = extractKey(req);
        if (!key) return rpcError(id, -32001, "Missing API key for metered tool", { hint: "Set Authorization: Bearer <key>" });
        const charge = chargeKey(key, action.cost);
        if (!charge.ok) return rpcError(id, -32002, charge.error, charge);
        auth = charge.auth;
      }

      try {
        const out = actions.invoke(name, args, auth);
        return rpcResult(id, {
          content: [{ type: "text", text: JSON.stringify(out, null, 2) }],
          structuredContent: out,
          isError: false
        });
      } catch (e) {
        return rpcResult(id, { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true });
      }
    }

    default:
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

router.get("/", (req, res) => res.json({
  service: SERVER_INFO, protocol: "mcp", protocolVersion: PROTOCOL_VERSION,
  transport: "streamable-http", endpoint: "/mcp",
  tools: actions.listActions().map((a) => a.name)
}));

router.post("/", (req, res) => {
  const body = req.body;
  if (Array.isArray(body)) {
    const responses = body.map((m) => handleOne(m, req)).filter((r) => r !== null);
    return res.json(responses);
  }
  const response = handleOne(body, req);
  if (response === null) return res.status(202).end(); // notification
  return res.json(response);
});

module.exports = router;
