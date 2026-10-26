"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { createAgentLayer } = require("../lib/agent");
const { createAgentGateway } = require("../lib/mcp/client");
const { handleRpc } = require("../lib/mcp/server");

for (const surface of ["agent", "MCP"]) {
  test(`admission: ${surface} malformed explicit events never invoke a provider`, async () => {
    let calls = 0;
    const layer = createAgentLayer({
      repoRoot: path.resolve(__dirname, "../../.."),
      env: { ANTHROPIC_API_KEY: "test-only-key", BRAHMA_CLAUDE_MODEL: "test-model" },
      transport: async () => {
        calls += 1;
        return JSON.stringify({ events: [{ time: 0, note: 60 }], summary: "test fixture" });
      }
    });
    const api = createAgentGateway({ agent: layer, role: "agent" });
    const results = [];
    for (const events of [null, [], {}, "not an event array"]) {
      const args = { provider: "claude", prompt: "must not call a provider", events };
      if (surface === "agent") results.push(await layer.propose(args));
      else {
        const out = await handleRpc({
          jsonrpc: "2.0", id: 1, method: "tools/call",
          params: { name: "brahma_propose_pattern", arguments: args }
        }, { role: "agent", api });
        results.push(out.result.structuredContent);
      }
    }
    assert.equal(calls, 0, "invalid explicit events must not fall through to paid composition");
    assert.deepEqual(results.map((result) => result.code), ["bad_events", "bad_events", "bad_events", "bad_events"]);
    assert.equal(layer.approvals.list().length, 0);
    const supplied = await layer.propose({ events: [{ time: 0, note: 60 }], provider: "claude" });
    assert.equal(supplied.ok, true);
    assert.equal(calls, 0, "valid explicit events remain the no-provider path");
  });
}
