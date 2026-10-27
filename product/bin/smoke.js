"use strict";
/**
 * smoke.js — End-to-end smoke test across every surface.
 *
 * Boots the server on an ephemeral port and exercises REST, MCP, ACP (both),
 * metering, and the billing stub. Exits non-zero on the first failure.
 *
 *   node bin/smoke.js
 */

const path = require("path");
const os = require("os");
const fs = require("fs");

const SPECIMENS_DIR = path.join(os.tmpdir(), "brahma-foundry-specimens-" + Date.now());
process.env.FOUNDRY_DATA_DIR = path.join(os.tmpdir(), "brahma-foundry-smoke-" + Date.now());
process.env.BRAHMA_SPECIMENS_DIR = SPECIMENS_DIR; // where wired specimen audio is streamed from
process.env.OSC_RECV_PORT = "0"; // avoid binding the real OSC port during tests
process.env.PORT = "0";
process.env.NODE_ENV = "test";
process.env.STRIPE_SECRET_KEY = "";
process.env.STRIPE_WEBHOOK_SECRET = "";
process.env.FOUNDRY_ALLOW_STUB_BILLING = "1";

const { server } = require("../server");
const { collection } = require("../src/core/store");

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass++; console.log(`  ✓ ${name}`); }
  else { fail++; console.error(`  ✗ ${name}`, extra != null ? JSON.stringify(extra) : ""); }
}

async function main() {
  await new Promise((r) => server.listening ? r() : server.once("listening", r));
  const port = server.address().port;
  const base = `http://127.0.0.1:${port}`;
  const J = async (res) => ({ status: res.status, body: await res.json().catch(() => ({})) });

  // 1. REST meta + catalog
  let r = await J(await fetch(`${base}/api/v1`));
  check("GET /api/v1 lists surfaces", r.status === 200 && r.body.data.surfaces.mcp === "/mcp");

  r = await J(await fetch(`${base}/api/v1/modules`));
  check("GET /modules returns catalog", r.status === 200 && r.body.data.length >= 10, r.body.data && r.body.data.length);

  // 2. Account signup → get API key
  const email = `smoke_${Date.now()}@brahma.test`;
  r = await J(await fetch(`${base}/api/v1/account/signup`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, password: "smoke-pass-123" }) }));
  check("POST /account/signup issues api key", r.status === 200 && r.body.data.apiKey, r.body);
  const apiKey = r.body.data && r.body.data.apiKey;

  // 3. Metered render with key
  r = await J(await fetch(`${base}/api/v1/render`, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` }, body: JSON.stringify({ module: "Azoth" }) }));
  check("POST /render (metered) succeeds", r.status === 200 && r.body.data.specimen.sourceModule === "Azoth", r.body);
  check("render usage incremented", r.body.data && r.body.data.usage && r.body.data.usage.count === 1, r.body.data && r.body.data.usage);

  // 4. Render without key is rejected
  r = await J(await fetch(`${base}/api/v1/render`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ module: "Azoth" }) }));
  check("POST /render without key → 401", r.status === 401, r.status);

  // 5. MCP: tools/list + tools/call
  r = await J(await fetch(`${base}/mcp`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }) }));
  check("MCP tools/list returns tools", r.status === 200 && r.body.result.tools.some((t) => t.name === "render_specimen"), r.body);

  r = await J(await fetch(`${base}/mcp`, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` }, body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "list_modules", arguments: {} } }) }));
  check("MCP tools/call list_modules works", r.status === 200 && !r.body.result.isError, r.body);

  r = await J(await fetch(`${base}/mcp`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "render_specimen", arguments: { module: "Nebula" } } }) }));
  check("MCP costed tool without key → JSON-RPC error", r.status === 200 && r.body.error && r.body.error.code === -32001, r.body);

  // 6. ACP (Agent Communication Protocol)
  r = await J(await fetch(`${base}/acp/agents`));
  check("ACP GET /agents lists brahma", r.status === 200 && r.body.agents[0].name === "brahma", r.body);

  r = await J(await fetch(`${base}/acp/runs`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ agent_name: "brahma", input: [{ parts: [{ content: "list modules" }] }] }) }));
  check("ACP POST /runs completes", r.status === 200 && r.body.status === "completed", r.body);

  // 7. ACP (Agent Client Protocol JSON-RPC)
  r = await J(await fetch(`${base}/acp/jsonrpc`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "session/prompt", params: { prompt: "show organism state" } }) }));
  check("ACP jsonrpc session/prompt works", r.status === 200 && r.body.result.stopReason === "end_turn", r.body);

  // 8. Plans + billing stub checkout
  r = await J(await fetch(`${base}/api/v1/plans`));
  check("GET /plans returns tiers", r.status === 200 && r.body.data.length >= 3, r.body);

  r = await J(await fetch(`${base}/api/v1/billing/checkout/plan`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, plan: "creator" }) }));
  check("checkout returns a url (stub or stripe)", r.status === 200 && r.body.data.checkoutUrl, r.body);

  // 9. Waitlist
  r = await J(await fetch(`${base}/api/v1/waitlist`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: `wl_${Date.now()}@brahma.test` }) }));
  check("POST /waitlist joins", r.status === 200 && r.body.data.joined, r.body);

  // 10. AETHER radio-station home (the funnel landing) is served at /
  const home = await fetch(`${base}/`);
  const homeHtml = await home.text();
  check("GET / serves the AETHER radio home", home.status === 200 && /AETHER/.test(homeHtml) && /home\.js/.test(homeHtml), home.status);

  // 11. Specimen audio streaming — the wired 501 stub (rest.js).
  fs.mkdirSync(SPECIMENS_DIR, { recursive: true });
  fs.writeFileSync(path.join(SPECIMENS_DIR, "specimen-real.wav"), Buffer.alloc(4096, 1)); // stand-in bytes; type is by extension
  const realId = "spec_real_" + Date.now();
  collection("specimens").insert({ id: realId, title: "Real Specimen", creator: "brahma", sourceModule: "Azoth", audioUrl: "specimen-real.wav", forSale: true, simulated: false, createdAt: new Date().toISOString() });

  let ar = await fetch(`${base}/api/v1/specimens/${realId}/audio`);
  const abuf = await ar.arrayBuffer();
  check("GET /specimens/:id/audio streams the real file (200)",
    ar.status === 200 && ar.headers.get("content-type") === "audio/wav" && abuf.byteLength === 4096,
    { status: ar.status, ct: ar.headers.get("content-type"), len: abuf.byteLength });
  check("audio endpoint advertises Range support", ar.headers.get("accept-ranges") === "bytes");

  ar = await fetch(`${base}/api/v1/specimens/${realId}/audio`, { headers: { Range: "bytes=0-99" } });
  const pbuf = await ar.arrayBuffer();
  check("audio Range request → 206 partial content",
    ar.status === 206 && pbuf.byteLength === 100 && /bytes 0-99\/4096/.test(ar.headers.get("content-range") || ""),
    { status: ar.status, len: pbuf.byteLength, cr: ar.headers.get("content-range") });

  // simulated specimen → 409 (unchanged honest behavior)
  const simId = "spec_sim_" + Date.now();
  collection("specimens").insert({ id: simId, title: "Sim", creator: "brahma", simulated: true, forSale: true, createdAt: new Date().toISOString() });
  r = await J(await fetch(`${base}/api/v1/specimens/${simId}/audio`));
  check("simulated specimen audio → 409", r.status === 409, r.status);

  // real specimen whose file is missing → 404 (not a false 200)
  const missId = "spec_miss_" + Date.now();
  collection("specimens").insert({ id: missId, title: "Miss", creator: "brahma", simulated: false, audioUrl: "nope.wav", forSale: true, createdAt: new Date().toISOString() });
  r = await J(await fetch(`${base}/api/v1/specimens/${missId}/audio`));
  check("real specimen, missing file → 404", r.status === 404, r.status);

  console.log(`\nSmoke: ${pass} passed, ${fail} failed`);
  server.close();
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error("smoke crashed:", e); process.exit(1); });
