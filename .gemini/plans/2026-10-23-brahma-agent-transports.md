# Plan — Brahma agent transports: Claude, Codex, OpenCode, agy

Date: 2026-10-23 · Repo: `alchemical-synthesizer` · Branch: `feat/brahma-live-workbench`
Continues `.gemini/plans/2026-10-23-brahma-workbench-continued.md` (M1.5–M5).
PR #56 stays **draft and unmerged**: this increment extends its report, it does not close it.

## 1. Request and verified state

Request: the compose loop must be reachable from the agent clients this host actually runs —
Claude Code, Codex, OpenCode, agy (Antigravity) — not only from `POST /api/agent/*`.

Verified live before planning:

| Claim | Check | Result |
|---|---|---|
| Gateway exposes propose/accept/run only over HTTP | `brahma/web/server.js:200-244` | true |
| Agent layer is transport-agnostic | `lib/agent/index.js` — no `req`/`res` dependency | true |
| `product/` already has MCP + ACP skins | `product/src/api/{mcp,acp}.js` | true, but over the **catalog** core (`product/src/core/actions.js`), not the compose loop |
| Clients on this host speak MCP | Codex `config.toml` `[mcp_servers.*]`; OpenCode `mcp.ianva` remote; agy `~/.gemini/config/mcp_config.json`; Claude project `.mcp.json` | true |
| Agent token is knowable by a client | random per launch unless `BRAHMA_AGENT_TOKEN` is set | **gap** — a stdio bridge cannot authenticate |

## 2. Decision

One capability surface, two role-scoped tool lists, two transports.

- **MCP (stdio)** is the universal path: all four clients spawn a stdio server. This is the
  primary transport.
- **MCP (HTTP JSON-RPC)** at `/mcp` is the zero-process path for clients that speak streamable
  HTTP (Codex, OpenCode, Claude Code). Same handler, same tool list.
- **ACP is rejected for this increment** with rationale: the four named clients speak MCP;
  `product/` already owns the ACP skin for editors (Zed). Adding a third skin here would be
  parallel substrate for no requested consumer.
- **`product/` is not forked.** Its MCP remains the metered marketplace surface. The compose
  loop executes local processes under a per-launch human token, so it stays beside the
  gateway. The *pattern* is reused: capability body, protocol skin.

### The human gate is structural, not advisory

| Role | Tools | Why |
|---|---|---|
| `agent` (default) | `brahma_provider_status`, `brahma_propose_pattern`, `brahma_approvals`, `brahma_job`, `brahma_engine_status` | An agent can file work and observe it. It cannot accept or run. |
| `human` (opt-in) | shared tools + `brahma_accept`, `brahma_reject`, `brahma_run` | `BRAHMA_MCP_ROLE=human` plus the human token is a human-authorized configuration. The workbench stays the canonical gate. |

`brahma_accept` and `brahma_run` are **absent from the agent tool list**, so an agent cannot
call them even by guessing a name (`tools/call` returns `unknown_tool`). The gateway still
re-checks the role (`actor: "human"` is only synthesised after `auth.roleOf(req) === "human"`),
so both layers agree.

Token handoff: the gateway writes the **agent** token to `brahma/web/.runtime/agent-token`
(0700 dir, 0600 file, gitignored) at boot. The human token is never written to disk. A stdio
bridge with no `BRAHMA_AGENT_TOKEN` reads that file, so the four clients work without copying
a secret into config.

## 3. Stages

| Stage | Work | Gate |
|---|---|---|
| T1 | `lib/mcp/server.js` — role-scoped tool registry, JSON-RPC handler, measured-not-heard descriptions | unit tests: role lists, error shapes |
| T2 | `lib/mcp/client.js` — HTTP gateway client + in-process gateway adapter | unit tests with a fake API |
| T3 | `bin/brahma-mcp.js` — stdio transport; token resolution; one-shot stdin | spawn test against a live test server |
| T4 | `server.js` — mount `POST/GET /mcp`, write agent token file, reuse runtime snapshot | HTTP role tests |
| T5 | Examples + docs for all four clients; root `.mcp.json` | file presence, valid JSON/TOML |
| T6 | `tools/smoke.sh` — MCP handshake + role-scoped tool assertion + stdio one-shot | smoke `--strict` |
| T7 | PR #56 report extension: Implemented / Tested / Observed per transport | report matches live evidence |

## 4. Non-goals / rejected

- No auto-run, no "accept and run" convenience tool.
- No token embedded in committed config; examples use environment/file resolution.
- No mutation of the host's global Codex/OpenCode/agy config — examples are copied by the
  operator, per "fix bases, not outputs".
- No synchronous wait inside `brahma_run`; `brahma_job(waitMs)` is bounded at 30 s.

## 5. Evidence to collect

1. `npm --prefix brahma/web test` — all files, including `mcp.test.js`.
2. `bash tools/smoke.sh --strict` — MCP checks pass.
3. Live: gateway boot, `tools/list` as agent (no accept/run), propose, workbench accept, human
   `brahma_run`, `brahma_job` returns the job; measured WAV summary unchanged.
4. Each client: config parses; initialize + tools/list observed. Where a client cannot be
   driven non-interactively (agy GUI), record `not_observed` rather than claiming success.

## 6. Human gates (unchanged)

- Audible confirmation of a rendered pattern.
- `ANTHROPIC_API_KEY` + `BRAHMA_CLAUDE_MODEL` for the Claude provider.
- AGPL / hosted-service legal question.

---

Merged: #56 / 99382c0 (squash merge commit `99382c0434611474634af8a8801c0bb43bd3b1f0`; merged tree `d5b3a948db6e17a1e0bad6f72cf52095428fc1d2`; verified head `e65d44d`; issue #55 CLOSED; PRs #52/#54 superseded by #56).
