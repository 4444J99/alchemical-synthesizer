#!/usr/bin/env node
"use strict";
/**
 * brahma-mcp.js — MCP over stdio, the transport every named client speaks.
 *
 *   Claude Code  .mcp.json            { "command": "node", "args": ["brahma/web/bin/brahma-mcp.js"] }
 *   Codex        config.toml         [mcp_servers.brahma] command/args
 *   OpenCode     opencode.json       mcp.brahma = { "type": "local", "command": [...] }
 *   agy          mcp_config.json     mcpServers.brahma = { "command": ..., "args": [...] }
 *
 * Default role is `agent`: propose and observe, never accept or run. Start with
 * --role human (or BRAHMA_MCP_ROLE=human) plus the human token to expose the
 * decision tools. That is a human-authorized configuration, not an agent default.
 *
 * stdout carries JSON-RPC only. Diagnostics go to stderr.
 */

const { createHttpGateway, resolveToken } = require("../lib/mcp/client");
const { handleRpc } = require("../lib/mcp/server");

const argv = process.argv.slice(2);

function flag(name, fallback) {
  const i = argv.indexOf(`--${name}`);
  if (i >= 0 && i + 1 < argv.length && !argv[i + 1].startsWith("--")) return argv[i + 1];
  return fallback;
}

const role = String(flag("role", process.env.BRAHMA_MCP_ROLE || "agent")).toLowerCase();
if (role !== "agent" && role !== "human") {
  process.stderr.write(`[brahma-mcp] unknown role "${role}" — use agent or human\n`);
  process.exit(2);
}

const baseUrl = flag("url", process.env.BRAHMA_GATEWAY_URL || `http://127.0.0.1:${process.env.PORT || 3000}`);
const tokenFile = flag("token-file", undefined);

function portOf(url) {
  try {
    const u = new URL(url);
    if (u.port) return Number(u.port);
    return u.protocol === "https:" ? 443 : 80;
  } catch (_) {
    return 3000;
  }
}

const token = resolveToken({ role, tokenFile, port: portOf(baseUrl) }); // allow-secret

if (!token) {
  const hint = role === "human"
    ? "set BRAHMA_HUMAN_TOKEN (the #t= value in the workbench launch URL) or pass --token-file"
    : `start the gateway first (it writes brahma/web/.runtime/agent-token-${portOf(baseUrl)}) or set BRAHMA_AGENT_TOKEN`;
  process.stderr.write(`[brahma-mcp] no ${role} token — ${hint}\n`);
  process.exit(2);
}

const api = createHttpGateway({ baseUrl, token, role });

let buffer = "";
let chain = Promise.resolve();

function emit(payload) {
  if (payload === null || payload === undefined) return;
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

async function dispatch(line) {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch (_) {
    emit({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
    return;
  }

  const messages = Array.isArray(msg) ? msg : [msg];
  const responses = [];
  for (const one of messages) {
    try {
      const out = await handleRpc(one, { role, api });
      if (out !== null) responses.push(out);
    } catch (err) {
      responses.push({
        jsonrpc: "2.0",
        id: one && one.id != null ? one.id : null,
        error: { code: -32603, message: err && err.message ? err.message : String(err) }
      });
    }
  }

  if (responses.length === 0) return;
  if (Array.isArray(msg)) emit(responses);
  else emit(responses[0]);
}

process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let nl;
  while ((nl = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, nl).trim();
    buffer = buffer.slice(nl + 1);
    if (!line) continue;
    chain = chain.then(() => dispatch(line));
  }
});

process.stdin.on("end", () => {
  chain.then(() => process.exit(0));
});

process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));
process.on("unhandledRejection", (err) => {
  process.stderr.write(`[brahma-mcp] unhandled: ${err && err.message ? err.message : String(err)}\n`);
});

process.stderr.write(`[brahma-mcp] ready — role=${role} gateway=${baseUrl}\n`);
