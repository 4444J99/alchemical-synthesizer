"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const LIVE_GATEWAY_SCD = path.resolve(__dirname, "../../sc/31_live_gateway.scd");
const LOADER_SCD = path.resolve(__dirname, "../../sc/loader.scd");
const SAFETY_SCD = path.resolve(__dirname, "../../sc/07_safety.scd");
const SERVER_JS = path.resolve(__dirname, "../server.js");

test("Live Bridge — SuperCollider File & Schema Integrity", async (t) => {
  await t.test("31_live_gateway.scd exists and defines required OSCdefs", () => {
    assert.ok(fs.existsSync(LIVE_GATEWAY_SCD), "31_live_gateway.scd must exist");
    const content = fs.readFileSync(LIVE_GATEWAY_SCD, "utf8");
    assert.ok(content.includes('OSCdef(\\live_play'), "Must define OSCdef(\\live_play)");
    assert.ok(content.includes('OSCdef(\\live_set'), "Must define OSCdef(\\live_set)");
    assert.ok(content.includes('OSCdef(\\live_panic'), "Must define OSCdef(\\live_panic)");
    assert.ok(content.includes('OSCdef(\\live_ping'), "Must define OSCdef(\\live_ping)");
  });

  await t.test("loader.scd loads 31_live_gateway.scd inside doWhenBooted", () => {
    const loader = fs.readFileSync(LOADER_SCD, "utf8");
    assert.ok(loader.includes('"31_live_gateway.scd"'), "loader.scd must load 31_live_gateway.scd");
    const gatewayIdx = loader.indexOf('"31_live_gateway.scd"');
    const respondersIdx = loader.indexOf('"16_engine_responders.scd"');
    assert.ok(gatewayIdx > respondersIdx, "31_live_gateway.scd must load after 16_engine_responders.scd");
  });

  await t.test("IMMUNE Safety Governor Preservation Invariant", () => {
    const gateway = fs.readFileSync(LIVE_GATEWAY_SCD, "utf8");
    // Invariant: s.freeAll must NEVER be called in live_panic
    const codeOnly = gateway.replace(/\/\*[\s\S]*?\*\/|\/\/.*/g, "");
    assert.ok(!codeOnly.includes("s.freeAll"), "CRITICAL: 31_live_gateway.scd must NEVER execute s.freeAll");
    assert.ok(!codeOnly.includes("Server.default.freeAll"), "Must not call Server.default.freeAll");

    // Verify panic cleans tasks, transports, voices and module instances
    assert.ok(gateway.includes("~live_gateway[\\tasks].do"), "Panic must cancel auto-release tasks");
    assert.ok(gateway.includes("~engine_voices.do"), "Panic must free engine voices");
    assert.ok(gateway.includes("~module_registry[\\modules].do"), "Panic must free module instances");
    assert.ok(gateway.includes("/brahma/live/panic/done"), "Panic must send confirmation reply");

    // Verify loader deploys stereo immune governor to ~sc_grp[\rr]
    const loader = fs.readFileSync(LOADER_SCD, "utf8");
    assert.ok(loader.includes("Synth(\\immune_governor"), "loader must deploy \\immune_governor");
    assert.ok(loader.includes("~sc_grp[\\rr]"), "immune_governor must be in group ~sc_grp[\\rr]");
  });

  await t.test("/brahma/live/play auto-release duration contract", () => {
    const gateway = fs.readFileSync(LIVE_GATEWAY_SCD, "utf8");
    assert.ok(gateway.includes("maxVoiceSecs: 30"), "Max voice duration must be capped at 30s");
    assert.ok(gateway.includes("task = Routine({"), "Must create auto-release Routine");
    assert.ok(gateway.includes("dur.wait;"), "Auto-release must wait for dur");
    assert.ok(gateway.includes("/brahma/engine/noteOff"), "Auto-release must trigger noteOff");
  });
});

test("Live Bridge — Gateway Server Namespace Whitelist", () => {
  const serverContent = fs.readFileSync(SERVER_JS, "utf8");
  assert.ok(serverContent.includes('"/brahma/"'), "server.js ALLOWED_NAMESPACES must include /brahma/");
  assert.ok(serverContent.includes('"/dirt/"'), "server.js ALLOWED_NAMESPACES must include /dirt/");
});
