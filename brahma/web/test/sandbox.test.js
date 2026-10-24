"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const sandbox = require("../lib/sandbox");
const runtimes = require("../lib/runtimes");

test("Suite 1: Sandbox Backend & Profile Generation", async (t) => {
  await t.test("backend() identifies seatbelt on darwin", () => {
    if (process.platform === "darwin" && fs.existsSync("/usr/bin/sandbox-exec")) {
      assert.equal(sandbox.backend(), "seatbelt");
    } else {
      assert.equal(sandbox.backend(), null);
    }
  });

  await t.test("buildProfile() generates deny-default Seatbelt syntax", () => {
    const scratch = "/tmp/dummy-scratch";
    const profile = sandbox.buildProfile({
      readRoots: ["/usr/lib"],
      readFiles: ["/tmp/file.js"],
      execs: [process.execPath],
      scratch,
      udpPort: 57120
    });

    assert.match(profile, /\(version 1\)/);
    assert.match(profile, /\(deny default\)/);
    assert.match(profile, /\(deny network\*\)/);
    assert.match(profile, /\(allow network-outbound \(remote udp "localhost:57120"\)\)/);
    assert.match(profile, /\(allow process-exec \(literal "[^"]+"\)\)/);
  });
});

test("Suite 2: Scratch Directory Lifecycle", async (t) => {
  await t.test("makeScratch() creates directory with 0700 permissions", () => {
    const scratch = sandbox.makeScratch();
    try {
      assert.ok(fs.existsSync(scratch));
      const stat = fs.statSync(scratch);
      assert.equal(stat.mode & 0o777, 0o700);
    } finally {
      sandbox.rmScratch(scratch);
    }
  });

  await t.test("rmScratch() removes directory cleanly", () => {
    const scratch = sandbox.makeScratch();
    sandbox.rmScratch(scratch);
    assert.equal(fs.existsSync(scratch), false);
  });
});

test("Suite 3: Fail-Closed Self-Test Verification", async (t) => {
  if (sandbox.backend() === "seatbelt") {
    await t.test("selfTest() passes 7-point isolation verification", async () => {
      const res = await sandbox.selfTest({ udpPort: 57130 });
      assert.equal(res.ok, true);
      assert.equal(res.backend, "seatbelt");
      assert.deepEqual(res.checks, {
        write_scratch: "allowed",
        write_outside: "denied",
        read_canary: "denied",
        exec_shell: "denied",
        tcp: "denied",
        udp_other: "denied",
        udp_engine: "allowed"
      });
    });
  } else {
    await t.test("selfTest() returns no_backend when platform lacks Seatbelt", async () => {
      const res = await sandbox.selfTest();
      assert.equal(res.ok, false);
      assert.equal(res.reason, "no_backend");
    });
  }
});

test("Suite 4: Sandbox Resource Limits & Process Group Teardown", async (t) => {
  if (sandbox.backend() !== "seatbelt") return;

  await t.test("launch() terminates process exceeding outputBytes limit", async () => {
    const scratch = sandbox.makeScratch();
    const script = path.join(scratch, "flood.js");
    fs.writeFileSync(script, "while(true) console.log('A'.repeat(1000));");
    const spec = sandbox.nodeRuntimeSpec();
    const profile = sandbox.buildProfile({ ...spec, readFiles: [script], scratch, udpPort: 57130 });

    const handle = sandbox.launch({
      cmd: spec.execs[0],
      args: [script],
      profile,
      scratch,
      limits: { outputBytes: 2048, wallMs: 10000 }
    });
    const res = await handle.done;
    assert.equal(res.reason, "output_limit");
  });

  await t.test("launch() terminates process exceeding wallMs timeout", async () => {
    const scratch = sandbox.makeScratch();
    const script = path.join(scratch, "sleep.js");
    fs.writeFileSync(script, "setInterval(() => {}, 1000);");
    const spec = sandbox.nodeRuntimeSpec();
    const profile = sandbox.buildProfile({ ...spec, readFiles: [script], scratch, udpPort: 57130 });

    const handle = sandbox.launch({
      cmd: spec.execs[0],
      args: [script],
      profile,
      scratch,
      limits: { wallMs: 200 }
    });
    const res = await handle.done;
    assert.equal(res.reason, "wall_clock_timeout");
  });
});

test("Suite 5: Runtime Status Gating Matrix", async (t) => {
  await t.test("Strudel is always available (browser)", () => {
    const status = runtimes.getRuntimeStatus({ role: null, sandboxStatus: { ok: false } });
    assert.equal(status.strudel.available, true);
    assert.equal(status.strudel.execution, "browser");
  });

  await t.test("Tidal and Sonic Pi are reported not_installed", () => {
    const status = runtimes.getRuntimeStatus({ role: "human", sandboxStatus: { ok: true } });
    assert.equal(status.tidalcycles.available, false);
    assert.equal(status.tidalcycles.reason, "not_installed");
    assert.equal(status.sonicpi.available, false);
    assert.equal(status.sonicpi.reason, "not_installed");
  });

  await t.test("sclang is disabled if BRAHMA_ALLOW_SCLANG is not 1", () => {
    const status = runtimes.getRuntimeStatus({
      role: "human",
      env: { BRAHMA_ALLOW_SCLANG: "0" },
      sandboxStatus: { ok: true }
    });
    assert.equal(status.sclang.available, false);
    assert.equal(status.sclang.reason, "disabled_by_env");
  });

  await t.test("sclang requires human role", () => {
    const status = runtimes.getRuntimeStatus({
      role: "agent",
      env: { BRAHMA_ALLOW_SCLANG: "1" },
      sandboxStatus: { ok: true }
    });
    assert.equal(status.sclang.available, false);
    assert.equal(status.sclang.reason, "human_role_required");
  });

  await t.test("sclang fails closed if sandbox self-test failed", () => {
    const status = runtimes.getRuntimeStatus({
      role: "human",
      env: { BRAHMA_ALLOW_SCLANG: "1" },
      sandboxStatus: { ok: false, reason: "self_test_failed" }
    });
    assert.equal(status.sclang.available, false);
    assert.equal(status.sclang.reason, "sandbox_unavailable");
  });

  await t.test("sclang reports not_installed if binary missing", () => {
    const status = runtimes.getRuntimeStatus({
      role: "human",
      env: { BRAHMA_ALLOW_SCLANG: "1" },
      sandboxStatus: { ok: true },
      sclangBinary: null
    });
    assert.equal(status.sclang.available, false);
    assert.equal(status.sclang.reason, "not_installed");
  });

  await t.test("sclang reports available when all gates pass", () => {
    const status = runtimes.getRuntimeStatus({
      role: "human",
      env: { BRAHMA_ALLOW_SCLANG: "1" },
      sandboxStatus: { ok: true },
      sclangBinary: "/Applications/SuperCollider.app/Contents/MacOS/sclang"
    });
    assert.equal(status.sclang.available, true);
    assert.equal(status.sclang.binary, "/Applications/SuperCollider.app/Contents/MacOS/sclang");
    assert.equal(status.sclang.mode, "headless");
  });
});

test("Suite 6: Sclang Runtime Spec and Execution Guard", async (t) => {
  await t.test("sclangRuntimeSpec builds readRoots and execs for valid path", () => {
    // Test with mock or existing node binary path as a valid filesystem target
    const spec = sandbox.sclangRuntimeSpec(process.execPath);
    assert.ok(Array.isArray(spec.execs));
    assert.ok(spec.execs.length > 0);
    assert.ok(Array.isArray(spec.readRoots));
    assert.ok(spec.readRoots.some(r => r.includes("sc")));
  });

  await t.test("executeSclang throws when BRAHMA_ALLOW_SCLANG != 1", async () => {
    await assert.rejects(
      async () => {
        await runtimes.executeSclang({
          code: "1 + 1",
          env: { BRAHMA_ALLOW_SCLANG: "0" }
        });
      },
      { code: "sclang_disabled" }
    );
  });
});
