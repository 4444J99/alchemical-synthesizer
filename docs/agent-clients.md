# Agent clients — Claude, Codex, OpenCode, agy

The workbench compose loop is reachable over MCP, the one transport all four clients
speak. There is no per-client adapter to keep in sync: each client launches the same
stdio bridge, or connects to the same HTTP endpoint.

```
client ──stdio──> brahma/web/bin/brahma-mcp.js ──HTTP──> gateway :3000 ──> agent layer
client ──HTTP──────────────────────────────────────────> gateway :3000/mcp ──> agent layer
```

Both wires call `handleRpc` in `brahma/web/lib/mcp/server.js`, so the tool list and the
role rules are identical.

## The boundary

The loop is three separate acts: **propose**, **accept**, **run**.

| Role | Tools exposed | Can it make sound? |
|---|---|---|
| `agent` (default) | `brahma_provider_status`, `brahma_propose_pattern`, `brahma_approvals`, `brahma_job`, `brahma_engine_status` | No. Accept/run are not in the list at all. |
| `human` (opt-in) | the same, plus `brahma_accept`, `brahma_reject`, `brahma_run` | Only when a human runs it. Accepting still does not run. |

`brahma_run` queues a render and returns a job id immediately. `brahma_job` polls for
the measured summary. **Measured is not heard:** an audio analysis ran, nobody listened.
The tool descriptions say so, and `initialize.instructions` repeats it to the model.

The workbench at `/workbench/` remains the canonical human gate. The human-role MCP
server exists for a human who wants to decide from their own client; do not put the
human token in an agent's environment.

## Prerequisites

Start the gateway once. It writes the agent token to
`brahma/web/.runtime/agent-token-<port>` (0600), so the clients need no pasted secret:

```bash
cd brahma/web
npm start
# → VISUAL CORTEX ONLINE: http://127.0.0.1:3000
# → MCP (agent): http://127.0.0.1:3000/mcp
```

Zero-config check, before touching any client config:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  | node brahma/web/bin/brahma-mcp.js
```

A `serverInfo` line on stdout means the bridge found the token and the gateway. If it
prints `no agent token`, the gateway is not running (or it is on another port — set
`BRAHMA_GATEWAY_URL`).

## Claude Code

Project scope is already committed as `.mcp.json` at the repo root. Open Claude Code in
this repository and approve the server when prompted (project servers stay
`⏸ Pending approval` until the workspace is trusted):

```bash
claude            # run once in the repo, approve "brahma" in /mcp
claude mcp list   # shows brahma with a connection status
```

The equivalent one-liner, if you prefer user scope across projects:

```bash
claude mcp add --scope user brahma -- \
  node /Users/4jp/Workspace/library/shelves/organvm-ii-poiesis/alchemical-synthesizer/brahma/web/bin/brahma-mcp.js
```

## Codex

Append the block from [`brahma/web/examples/mcp/codex.config.toml`](../brahma/web/examples/mcp/codex.config.toml)
to `~/.codex/config.toml`, then restart Codex:

```toml
[mcp_servers.brahma]
command = "node"
args = ["/Users/4jp/Workspace/library/shelves/organvm-ii-poiesis/alchemical-synthesizer/brahma/web/bin/brahma-mcp.js"]
startup_timeout_sec = 20
```

## OpenCode

The current config shape is `mcp.servers.<name>` (verified with `opencode mcp add`):

```jsonc
{
  "mcp": {
    "servers": {
      "brahma": {
        "type": "local",
        "command": ["node", "/Users/4jp/Workspace/library/shelves/organvm-ii-poiesis/alchemical-synthesizer/brahma/web/bin/brahma-mcp.js"]
      }
    }
  }
}
```

Add it without hand-editing:

```bash
opencode mcp add brahma -- node /Users/4jp/Workspace/library/shelves/organvm-ii-poiesis/alchemical-synthesizer/brahma/web/bin/brahma-mcp.js
# add --global to write the user config instead of the project config
```

This host's `~/.config/opencode/opencode.json` still uses the legacy flat form
(`mcp.ianva`). The schema accepts it as deprecated, so you can either put `brahma`
beside `ianva` in the flat map or keep the new `mcp.servers` block; do not replace
`ianva`.

Restart OpenCode, then `opencode mcp list` shows the server.

## agy (Antigravity)

Merge the entry from [`brahma/web/examples/mcp/agy.mcp_config.json`](../brahma/web/examples/mcp/agy.mcp_config.json)
into `~/.gemini/config/mcp_config.json`, then reload the MCP panel:

```json
{
  "mcpServers": {
    "brahma": {
      "command": "node",
      "args": ["/Users/4jp/Workspace/library/shelves/organvm-ii-poiesis/alchemical-synthesizer/brahma/web/bin/brahma-mcp.js"]
    }
  }
}
```

If Antigravity's GUI cannot show the server, run the same command through its MCP
proxy (the host already uses `uvx mcp-proxy` for `ianva`).

The CLI writes that same file, which is the safest way to edit it:

```bash
agy mcp add brahma node /Users/4jp/Workspace/library/shelves/organvm-ii-poiesis/alchemical-synthesizer/brahma/web/bin/brahma-mcp.js
agy mcp list   # brahma  stdio  enabled  node …/brahma-mcp.js
```

## Human role (decision tools)

Only configure this in a client session a human controls. The token is the `#t=` value
in the workbench launch URL:

```bash
printf '%s' '<token-from-launch-url>' > ~/.brahma-human-token
chmod 600 ~/.brahma-human-token
node brahma/web/bin/brahma-mcp.js --role human --token-file ~/.brahma-human-token
```

For a client config, add `--role`, `human` to the args and either set
`BRAHMA_HUMAN_TOKEN` in that client's environment or pass `--token-file`. The human
token is never written to `.runtime/`.

## HTTP transport

For a client that prefers streamable HTTP, point it at `http://127.0.0.1:3000/mcp` with
the agent token as a bearer header:

```bash
# Codex-style
# [mcp_servers.brahma]
# url = "http://127.0.0.1:3000/mcp"
# http_headers = { Authorization = "Bearer <agent-token>" }
```

The token is in `brahma/web/.runtime/agent-token-3000`. The endpoint speaks JSON-RPC
over POST and returns JSON, not SSE.

## What a run looks like

```
Agent: brahma_propose_pattern { provider: "mock", prompt: "slow chord" }
       → { approval: { id: "apv_…", state: "proposed" } }   # nothing ran

Human (workbench or human-role client):
       brahma_accept { approvalId: "apv_…" }                 # nothing ran
       brahma_run    { approvalId: "apv_…" }                 # → { job: { id: "job_…" } }

Agent: brahma_job { jobId: "job_…", waitMs: 20000 }
       → { job: { state: "completed", result: { measured: { verdict: "non_silent", … } } } }
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `no agent token` on stderr, exit 2 | Gateway not running, or on another port | Start it; set `BRAHMA_GATEWAY_URL=http://127.0.0.1:<port>` |
| `401 auth_required` from `/mcp` | Missing/incorrect bearer token | Use the token file for the matching port, or set `BRAHMA_AGENT_TOKEN` |
| `unknown_tool: brahma_accept` | Agent-role server, as designed | Accept in the workbench, or start a human-role server |
| `human_role_required` | A human tool reached the gateway with an agent token | Same as above |
| `provider_unavailable` | Provider is honestly absent (`not_installed`, `not_configured`) | Use `mock`, or install/configure the provider |

## Why this is a second MCP surface

`product/src/api/mcp.js` exposes the metered marketplace catalog
(`render_specimen`, `list_modules`) to remote agents. The workbench loop executes local
processes under a per-launch human token, so it stays beside the gateway. The pattern is
the same — capability body, protocol skin — but the bodies are different. ACP stays in
`product/` for editors that speak it; none of the four named clients needs it here.
