"use strict";
/**
 * server.js — Model Context Protocol skin over the compose loop.
 *
 * The body is the same body the HTTP API uses: propose files an approval, a human
 * accepts it, and a separate human act runs it. This file adds no new authority; it
 * only renames those acts as MCP tools and decides which names a role may see.
 *
 *   role=agent  propose + observe. accept/run/reject are NOT in the tool list.
 *   role=human  the same, plus accept/reject/run. Opt-in, human-authorized.
 *
 * "Measured" in a tool result means an audio analysis ran. It does not mean the
 * pattern was heard. The description says so, because a model will otherwise
 * paraphrase it as "confirmed".
 */

const PROTOCOL_VERSION = "2025-06-18";
const SERVER_INFO = { name: "brahma-workbench", version: "0.1.0" };

const TERMINAL_JOB_STATES = new Set(["completed", "failed"]);
const APPROVAL_STATES = ["proposed", "accepted", "rejected", "running", "completed", "failed"];

const READ_ONLY = Object.freeze({ readOnlyHint: true, destructiveHint: false, openWorldHint: false });
const WRITES = Object.freeze({ readOnlyHint: false, destructiveHint: false, openWorldHint: false });

function rpcResult(id, result) { return { jsonrpc: "2.0", id, result }; }
function rpcError(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

async function waitForJob(api, id, waitMs) {
  const bounded = Math.min(Math.max(Number(waitMs) || 0, 0), 30000);
  const deadline = Date.now() + bounded;
  for (;;) {
    const out = await api.job(id);
    if (TERMINAL_JOB_STATES.has(out.job.state) || Date.now() >= deadline) {
      return { ...out, waitLimitMs: bounded };
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}

const SHARED_TOOLS = [
  {
    name: "brahma_provider_status",
    title: "Provider status",
    description:
      "List composition providers and whether each is actually available on this host, plus the tool catalogue. " +
      "An unavailable provider reports a reason (not_installed, not_configured); it never returns an empty pattern. " +
      "Call this before proposing.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: READ_ONLY,
    handler: async (_args, { api }) => api.providers()
  },
  {
    name: "brahma_propose_pattern",
    title: "Propose a pattern",
    description:
      "Turn a prompt into note events and file an approval in state 'proposed'. " +
      "Nothing is rendered, queued, or played. A human must accept the approval, then separately run it. " +
      "This tool cannot accept or run, by design.",
    inputSchema: {
      type: "object",
      required: ["prompt"],
      properties: {
        prompt: { type: "string", minLength: 1, description: "What to compose." },
        provider: { type: "string", enum: ["mock", "claude", "tidal", "sonicpi"], default: "mock" },
        duration: { type: "number", minimum: 0.5, maximum: 120, description: "Render length in seconds; omit to derive from the events." }
      },
      additionalProperties: false
    },
    annotations: WRITES,
    handler: async (args, { api }) => {
      if (!args.prompt || !String(args.prompt).trim()) {
        throw Object.assign(new Error("prompt is required"), { code: "bad_request" });
      }
      return api.propose({
        provider: args.provider || "mock",
        prompt: String(args.prompt),
        duration: args.duration
      });
    }
  },
  {
    name: "brahma_approvals",
    title: "List approvals",
    description:
      "List approval records and their states (proposed, accepted, rejected, running, completed, failed). " +
      "Use this to see whether a human has accepted a proposal. Listing changes nothing.",
    inputSchema: {
      type: "object",
      properties: {
        state: { type: "string", enum: APPROVAL_STATES, description: "Optional state filter." }
      },
      additionalProperties: false
    },
    annotations: READ_ONLY,
    handler: async (args, { api }) => {
      const body = await api.approvals();
      const approvals = Array.isArray(body.approvals) ? body.approvals : [];
      return { approvals: args.state ? approvals.filter((a) => a.state === args.state) : approvals };
    }
  },
  {
    name: "brahma_job",
    title: "Inspect a render job",
    description:
      "Inspect a render job by id. Optional waitMs (max 30000) polls until the job is no longer queued or running. " +
      "A completed job carries a measured audio summary (peak/rms/verdict). Measured is not heard: a human still has to listen.",
    inputSchema: {
      type: "object",
      required: ["jobId"],
      properties: {
        jobId: { type: "string", description: "Job id returned by brahma_run." },
        waitMs: { type: "integer", minimum: 0, maximum: 30000, description: "Poll up to this long for a terminal state." }
      },
      additionalProperties: false
    },
    annotations: READ_ONLY,
    handler: async (args, { api }) => {
      if (!args.jobId) throw Object.assign(new Error("jobId is required"), { code: "bad_request" });
      return waitForJob(api, String(args.jobId), args.waitMs);
    }
  },
  {
    name: "brahma_engine_status",
    title: "Gateway and engine status",
    description:
      "Report the gateway sandbox state and runtime availability (strudel, tidal, sonicpi, sclang). Read-only.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: READ_ONLY,
    handler: async (_args, { api }) => api.engine()
  }
];

const HUMAN_TOOLS = [
  {
    name: "brahma_accept",
    title: "Accept a proposal (human only)",
    description:
      "HUMAN ONLY. Move a proposed approval to accepted. This does not run it; brahma_run is a separate act. " +
      "Only exposed when the server was started with BRAHMA_MCP_ROLE=human and the human token.",
    inputSchema: {
      type: "object",
      required: ["approvalId"],
      properties: { approvalId: { type: "string" } },
      additionalProperties: false
    },
    annotations: WRITES,
    handler: async (args, { api }) => {
      if (!args.approvalId) throw Object.assign(new Error("approvalId is required"), { code: "bad_request" });
      return api.accept(String(args.approvalId));
    }
  },
  {
    name: "brahma_reject",
    title: "Reject a proposal (human only)",
    description: "HUMAN ONLY. Move a proposed or accepted approval to rejected. Nothing runs.",
    inputSchema: {
      type: "object",
      required: ["approvalId"],
      properties: {
        approvalId: { type: "string" },
        reason: { type: "string", maxLength: 500 }
      },
      additionalProperties: false
    },
    annotations: WRITES,
    handler: async (args, { api }) => {
      if (!args.approvalId) throw Object.assign(new Error("approvalId is required"), { code: "bad_request" });
      return api.reject(String(args.approvalId), args.reason);
    }
  },
  {
    name: "brahma_run",
    title: "Run an accepted proposal (human only)",
    description:
      "HUMAN ONLY. Queue an accepted approval for rendering and return immediately with a job id. " +
      "This shells out to sclang; poll brahma_job for the measured result. It does not wait.",
    inputSchema: {
      type: "object",
      required: ["approvalId"],
      properties: { approvalId: { type: "string" } },
      additionalProperties: false
    },
    annotations: Object.freeze({ readOnlyHint: false, destructiveHint: false, openWorldHint: false, idempotentHint: false }),
    handler: async (args, { api }) => {
      if (!args.approvalId) throw Object.assign(new Error("approvalId is required"), { code: "bad_request" });
      return api.run(String(args.approvalId));
    }
  }
];

/** The structural gate: an agent-role server cannot even name accept/run. */
function toolsFor(role) {
  return role === "human" ? SHARED_TOOLS.concat(HUMAN_TOOLS) : SHARED_TOOLS.slice();
}

function publicView(tool) {
  return {
    name: tool.name,
    title: tool.title,
    description: tool.description,
    inputSchema: tool.inputSchema,
    annotations: tool.annotations
  };
}

function instructionsFor(role) {
  const boundary = role === "human"
    ? "Role: human. You may accept, reject, and run. Accepting does not run; running is a separate call."
    : "Role: agent. You may propose patterns and inspect approvals and jobs. You cannot accept or run them: those tools are not exposed. Ask the human to accept in the workbench, or use a human-role server.";
  return [
    "Brahma workbench — local live-coding gateway.",
    boundary,
    "The loop is three separate acts: propose files an approval, a human accepts it, a human runs it.",
    "'Measured' in a job result means an audio analysis was computed. It does not mean the pattern was heard. Never claim audible confirmation from a measured summary."
  ].join(" ");
}

/**
 * Handle one JSON-RPC message. Returns the response object, or null for a
 * notification. Never throws for ordinary protocol misuse.
 */
async function handleRpc(msg, { role = "agent", api } = {}) {
  if (!msg || typeof msg !== "object" || msg.jsonrpc !== "2.0" || typeof msg.method !== "string") {
    return rpcError(msg && msg.id != null ? msg.id : null, -32600, "Invalid Request");
  }

  const { id, method, params } = msg;
  const notification = id === undefined || id === null;

  switch (method) {
    case "initialize":
      return rpcResult(id, {
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: SERVER_INFO,
        capabilities: { tools: { listChanged: false }, resources: {}, prompts: {} },
        instructions: instructionsFor(role)
      });

    case "notifications/initialized":
    case "notifications/cancelled":
      return null;

    case "ping":
      return rpcResult(id, {});

    case "tools/list":
      return rpcResult(id, { tools: toolsFor(role).map(publicView) });

    case "tools/call": {
      const name = params && params.name;
      const tool = toolsFor(role).find((t) => t.name === name);
      if (!tool) {
        return rpcResult(id, {
          content: [{ type: "text", text: `Error (unknown_tool): no tool ${name} for role ${role}` }],
          structuredContent: { ok: false, code: "unknown_tool", message: `no tool ${name} for role ${role}` },
          isError: true
        });
      }

      try {
        const out = await tool.handler((params && params.arguments) || {}, { role, api });
        return rpcResult(id, {
          content: [{ type: "text", text: JSON.stringify(out, null, 2) }],
          structuredContent: out,
          isError: false
        });
      } catch (err) {
        const code = err && err.code ? err.code : "tool_error";
        const message = err && err.message ? err.message : String(err);
        const payload = { ok: false, code, message };
        if (err && err.detail) payload.detail = err.detail;
        return rpcResult(id, {
          content: [{ type: "text", text: `Error (${code}): ${message}` }],
          structuredContent: payload,
          isError: true
        });
      }
    }

    case "resources/list":
      return rpcResult(id, { resources: [] });

    case "prompts/list":
      return rpcResult(id, { prompts: [] });

    case "logging/setLevel":
      return rpcResult(id, {});

    default:
      if (notification) return null;
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

module.exports = {
  PROTOCOL_VERSION,
  SERVER_INFO,
  SHARED_TOOLS,
  HUMAN_TOOLS,
  toolsFor,
  handleRpc,
  instructionsFor
};
