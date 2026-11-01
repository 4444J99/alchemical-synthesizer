"use strict";

// Regression for the signal path with work in flight. A SIGTERM/SIGINT that arrives
// while a render is running must cancel the render and its descendants, wait for them
// to settle, exit 0, and give any second signal back to the default action. The first
// version of the signal handler exited as soon as the HTTP server closed, which would
// have left a detached renderer running after the gateway reported a clean stop.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { EVENTS, bootGateway, gatewayHandlers, waitFor, within, delay } = require("./fixtures/shutdown-gateway");

let fixture = null;

test.before(async () => { fixture = await bootGateway(); });
test.after(() => { if (fixture) fixture.cleanup(); });

test("a signal cancels an active render, waits for it, exits 0 and releases both handlers",
  { skip: process.platform === "win32" }, async (t) => {
    const { gateway, heartbeat } = fixture;
    const exit = new Promise((resolve) => { t.mock.method(process, "exit", (code) => resolve(code)); });

    const queued = gateway.agent.runner.enqueue({ tool: "render_pattern", args: { events: EVENTS, duration: 1 } });
    assert.equal(queued.ok, true, JSON.stringify(queued));
    await waitFor(() => fs.existsSync(heartbeat), "renderer fixture did not start");
    assert.equal(gatewayHandlers("SIGTERM").length, 1);
    assert.equal(gatewayHandlers("SIGINT").length, 1);

    // Call the gateway's own handler; emitting the event would also run the test
    // runner's termination handler.
    gatewayHandlers("SIGTERM")[0]();

    const code = await within(exit, 5000, "gateway did not exit after the signal");
    assert.equal(code, 0);

    const job = gateway.agent.runner.get(queued.job.id);
    assert.equal(job.state, "failed", "the render must be cancelled before the gateway exits");
    assert.equal(job.error, "stopped by human");
    const size = fs.statSync(heartbeat).size;
    await delay(120);
    assert.equal(fs.statSync(heartbeat).size, size, "the renderer outlived the gateway's shutdown");

    assert.equal(gatewayHandlers("SIGTERM").length, 0, "the handler must release SIGTERM");
    assert.equal(gatewayHandlers("SIGINT").length, 0, "a second signal of the other kind must take the default action");
  });
