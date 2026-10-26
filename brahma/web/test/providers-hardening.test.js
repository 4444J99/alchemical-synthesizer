"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");
const { createProviderRegistry, validateEvents } = require("../lib/agent/providers");
const { defaultExecFile } = require("../lib/agent/tools");
const { createAgentLayer } = require("../lib/agent");
const { createAgentGateway } = require("../lib/mcp/client");
const { handleRpc } = require("../lib/mcp/server");

const PROVIDERS_PATH = require.resolve("../lib/agent/providers");

function temporaryDir(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-provider-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function ghciFixture(t, body) {
  const dir = temporaryDir(t);
  const marker = path.join(dir, "invocations");
  const script = "#!" + process.execPath + "\n" +
    "const fs=require('node:fs');\n" +
    "fs.appendFileSync(" + JSON.stringify(marker) + ", 'started\\n');\n" +
    (typeof body === "function" ? body({ dir, marker }) : body) + "\n";
  fs.writeFileSync(path.join(dir, "ghci"), script, { mode: 0o700 });
  return { dir, marker, env: { ...process.env, PATH: dir + path.delimiter + process.env.PATH } };
}

function status(registry, name) {
  return registry.list().find((provider) => provider.name === name);
}

test("providers: construction and listing do no optional-runtime work, and explicit discovery yields", async (t) => {
  const fixture = ghciFixture(t, "setTimeout(()=>process.stdout.write('TIDAL_OK\\n'), 200);");
  // A separate process gives the old synchronous probe the same PATH as the
  // explicit discovery, without changing this test runner's environment.
  const script = [
    "const fs=require('node:fs');",
    "const {createProviderRegistry}=require(" + JSON.stringify(PROVIDERS_PATH) + ");",
    "(async()=>{",
    "const registry=createProviderRegistry({env:process.env,probeTimeoutMs:2000});",
    "const initial=registry.list().find(p=>p.name==='tidal');",
    "const startedBeforeProbe=fs.existsSync(" + JSON.stringify(fixture.marker) + ");",
    "const probing=registry.probe();",
    "const first=await Promise.race([probing.then(()=> 'probe'),new Promise(r=>setTimeout(()=>r('timer'),10))]);",
    "const result=await probing;",
    "console.log(JSON.stringify({startedBeforeProbe,initial:initial.discovery,first,detected:result.tidal}));",
    "})().catch(e=>{console.error(e);process.exitCode=1;});"
  ].join("\n");
  const output = await defaultExecFile(process.execPath, ["-e", script], { env: fixture.env, timeout: 4000 });
  const result = JSON.parse(output.stdout.trim());
  assert.equal(result.startedBeforeProbe, false, "constructing/listing must not launch GHCi");
  assert.equal(result.initial.status, "not_probed");
  assert.equal(result.first, "timer", "discovery must not block the gateway event loop");
  assert.equal(result.detected, true);
});

test("providers: discovery timeout terminates the optional command and its descendants", {
  skip: process.platform === "win32"
}, async (t) => {
  let childFile;
  let heartbeat;
  const fixture = ghciFixture(t, ({ dir }) => {
    childFile = path.join(dir, "child.pid");
    heartbeat = path.join(dir, "heartbeat");
    const childCode = "const fs=require('node:fs');process.on('SIGTERM',()=>{});setInterval(()=>fs.appendFileSync(" +
      JSON.stringify(heartbeat) + ",'.'),10);";
    return "const child=require('node:child_process').spawn(process.execPath,['-e'," + JSON.stringify(childCode) +
      "],{stdio:['ignore','inherit','inherit']});fs.writeFileSync(" + JSON.stringify(childFile) +
      ",String(child.pid));setInterval(()=>{},1000);";
  });
  const registry = createProviderRegistry({ env: fixture.env, probeTimeoutMs:750 });
  try {
    const result = await registry.probe();
    assert.equal(result.tidal, false);
    assert.equal(status(registry, "tidal").discovery.status, "timeout");
    assert.ok(fs.existsSync(heartbeat), "the descendant must have actually started");
    const size = fs.statSync(heartbeat).size;
    assert.ok(size > 0);
    await delay(80);
    assert.equal(fs.statSync(heartbeat).size, size, "the discovery descendant kept running after timeout");
  } finally {
    if (fs.existsSync(childFile)) {
      try { process.kill(Number(fs.readFileSync(childFile, "utf8")), "SIGKILL"); } catch (_) {}
    }
  }
});

test("providers: a missing optional executable is reported as not installed", async (t) => {
  const registry = createProviderRegistry({ env: { PATH: temporaryDir(t) }, probeTimeoutMs:1000 });
  const result = await registry.probe();
  assert.equal(result.tidal, false);
  assert.equal(status(registry, "tidal").discovery.status, "not_installed");
  assert.match(status(registry, "tidal").discovery.reason, /ghci/);
  assert.equal(status(registry, "tidal").available, false);
});

test("providers: installed runtimes remain unavailable, and discovery is deduplicated and registry-local", async (t) => {
  const fixture = ghciFixture(t, "setTimeout(()=>process.stdout.write('TIDAL_OK\\n'), 100);");
  const access = fs.promises.access.bind(fs.promises);
  t.mock.method(fs.promises, "access", async (file, ...args) => {
    if (file === "/Applications/Sonic Pi.app") return;
    return access(file, ...args);
  });
  const first = createProviderRegistry({ env: fixture.env });
  const other = createProviderRegistry({ env: fixture.env });
  const results = await Promise.all([first.probe(), first.probe()]);
  assert.equal(results[0].tidal, true);
  assert.equal(results[0].sonicpi, true);
  assert.equal(fs.readFileSync(fixture.marker, "utf8").trim().split("\n").length, 1);
  assert.equal(status(other, "tidal").discovery.status, "not_probed");
  for (const name of ["tidal", "sonicpi"]) {
    assert.equal(status(first, name).discovery.status, "detected");
    assert.equal(status(first, name).available, false);
    assert.match(status(first, name).reason, /^adapter_not_implemented/);
    const result = await first.propose(name, { prompt: "must not play or invent a fixture" });
    assert.equal(result.code, "provider_unavailable");
    assert.equal(result.events, undefined);
  }
  assert.equal(fs.readFileSync(fixture.marker, "utf8").trim().split("\n").length, 1,
    "proposing must not invoke a runtime");
  status(first, "tidal").discovery.status = "tampered";
  assert.equal(status(first, "tidal").discovery.status, "detected", "status is a snapshot");
});

test("providers: missing or blank model configuration cannot call a model transport", async () => {
  const cases = [
    ["claude", {}],
    ["claude", { ANTHROPIC_API_KEY: "test-key" }],
    ["claude", { BRAHMA_CLAUDE_MODEL: "explicit-model" }],
    ["claude", { ANTHROPIC_API_KEY: " ", BRAHMA_CLAUDE_MODEL: "explicit-model" }],
    ["claude", { ANTHROPIC_API_KEY: "test-key", BRAHMA_CLAUDE_MODEL: " " }],
    ["gemini", {}],
    ["gemini", { GEMINI_API_KEY: "test-key" }],
    ["gemini", { GOOGLE_API_KEY: "test-key" }],
    ["gemini", { BRAHMA_GEMINI_MODEL: "explicit-model" }],
    ["gemini", { GEMINI_API_KEY: " ", BRAHMA_GEMINI_MODEL: "explicit-model" }],
    ["gemini", { GEMINI_API_KEY: "test-key", BRAHMA_GEMINI_MODEL: " " }]
  ];
  let calls = 0;
  for (const [name, env] of cases) {
    const registry = createProviderRegistry({ env, transport: async () => { calls += 1; return "{}"; } });
    assert.equal(status(registry, name).available, false, name + " requires a key and an explicit model");
    assert.match(status(registry, name).reason, /^not_configured/);
    const result = await registry.propose(name, { prompt: "no configuration, no call" });
    assert.equal(result.code, "provider_unavailable");
  }
  assert.equal(calls, 0);
});

test("providers: configured Gemini is discoverable and proposes over MCP without a live call", async () => {
  const calls = [];
  const layer = createAgentLayer({
    repoRoot: path.resolve(__dirname, "../../.."),
    env: { GEMINI_API_KEY: " ", GOOGLE_API_KEY: " test-key ", BRAHMA_GEMINI_MODEL: " explicit-gemini " },
    transport: async (request) => {
      calls.push(request);
      return JSON.stringify({ summary: "transport fixture", events: [{ time:1, note:64 }, { time:0, note:60 }] });
    }
  });
  const api = createAgentGateway({ agent: layer, role: "agent" });
  const listed = await handleRpc({ jsonrpc:"2.0", id:1, method:"tools/list" }, { role:"agent", api });
  const schema = listed.result.tools.find((tool) => tool.name === "brahma_propose_pattern").inputSchema;
  assert.ok(schema.properties.provider.enum.includes("gemini"));
  assert.deepEqual(schema.properties.provider.enum, layer.providers.names());
  assert.equal(status(layer.providers, "gemini").available, true);
  const response = await handleRpc({
    jsonrpc:"2.0", id:2, method:"tools/call",
    params:{ name:"brahma_propose_pattern", arguments:{ provider:"gemini", prompt:"a test motif" } }
  }, { role:"agent", api });
  assert.equal(response.result.isError, false);
  assert.equal(response.result.structuredContent.approval.state, "proposed");
  assert.deepEqual(response.result.structuredContent.events.map((event) => event.note), [60, 64]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].model, "explicit-gemini");
  assert.equal(calls[0].apiKey, "test-key");
  assert.equal(layer.runner.list().length, 0, "a provider proposal must not execute a render");
});

test("providers: malformed event elements are refused without throwing", () => {
  for (const event of [null, 0, "note", []]) {
    assert.equal(validateEvents([event]), null);
  }
});


test("providers: close cancels pending discovery and prevents another subprocess", async (t) => {
  const fixture = ghciFixture(t, "setInterval(()=>{}, 1000);");
  const registry = createProviderRegistry({ env: fixture.env, probeTimeoutMs: 1500 });
  const pending = registry.probe();
  const deadline = Date.now() + 1000;
  while (!fs.existsSync(fixture.marker)) {
    assert.ok(Date.now() < deadline, "the probe must actually start");
    await delay(10);
  }
  registry.close();
  assert.equal((await pending).tidal, false);
  assert.equal(status(registry, "tidal").discovery.status, "closed");
  assert.deepEqual(await registry.probe(), { tidal: false, sonicpi: false });
  assert.equal(fs.readFileSync(fixture.marker, "utf8"), "started\n");
});
