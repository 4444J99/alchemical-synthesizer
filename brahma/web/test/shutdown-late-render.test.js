"use strict";

// A request that is still being served when the signal arrives can finish, and start
// a render, after the first cancellation. The server only reports closed once such a
// request is done, so the shutdown must cancel again at that point; otherwise it would
// wait on a render nobody can stop and leave it running when the grace timer expires.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { EVENTS, bootGateway, gatewayHandlers, waitFor, within, delay } = require("./fixtures/shutdown-gateway");

let fixture = null;

test.before(async () => { fixture = await bootGateway({ graceMs: 1500 }); });
test.after(() => { if (fixture) fixture.cleanup(); });

test("a render started by a request that outlives the signal is cancelled before exit",
  { skip: process.platform === "win32" }, async (t) => {
    const { gateway, heartbeat } = fixture;
    const exit = new Promise((resolve) => { t.mock.method(process, "exit", (code) => resolve(code)); });

    // Hold server.close() open, as an in-flight request would, until we release it.
    const realClose = gateway.server.close.bind(gateway.server);
    let release = null;
    t.mock.method(gateway.server, "close", (callback) => { release = callback; });

    gatewayHandlers("SIGTERM")[0]();
    assert.equal(typeof release, "function", "the handler must wait on server.close()");

    // The in-flight request completes after the first cancellation and starts a render.
    const queued = gateway.agent.runner.enqueue({ tool: "render_pattern", args: { events: EVENTS, duration: 1 } });
    assert.equal(queued.ok, true, JSON.stringify(queued));
    await waitFor(() => fs.existsSync(heartbeat), "renderer fixture did not start");

    release();
    const code = await within(exit, 4000, "gateway did not exit after the signal");
    assert.equal(code, 0, "the late render must be cancelled so the drain can finish inside the grace period");

    const job = gateway.agent.runner.get(queued.job.id);
    assert.equal(job.state, "failed");
    assert.equal(job.error, "stopped by human");
    const size = fs.statSync(heartbeat).size;
    await delay(120);
    assert.equal(fs.statSync(heartbeat).size, size, "the late render outlived the gateway's shutdown");

    realClose();
  });
