"use strict";
/**
 * runtimes.js — Sandboxed execution harnesses and status reporting for language runtimes.
 *
 * Runtimes supported:
 *   - strudel: browser-side client execution (always available)
 *   - tidalcycles: sandboxed server execution (reported not_installed)
 *   - sonicpi: sandboxed server execution (reported not_installed)
 *   - sclang: SuperCollider sclang execution (opt-in behind BRAHMA_ALLOW_SCLANG=1 and human role)
 */

const fs = require("fs");
const path = require("path");
const sandbox = require("./sandbox");

/**
 * Searches standard macOS application paths, Homebrew paths, and environment overrides
 * for the SuperCollider sclang executable.
 * @returns {string|null} Resolved absolute path or null if not found
 */
function findSclang() {
  const candidates = [
    process.env.SCLANG_PATH,
    "/Applications/SuperCollider.app/Contents/MacOS/sclang",
    "/Applications/SuperCollider/SuperCollider.app/Contents/MacOS/sclang",
    "/usr/local/bin/sclang",
    "/opt/homebrew/bin/sclang"
  ].filter(Boolean);

  for (const c of candidates) {
    try {
      if (fs.existsSync(c) && fs.statSync(c).isFile()) {
        return fs.realpathSync(c);
      }
    } catch (_) {}
  }
  return null;
}

/**
 * Evaluates runtime availability against caller role, environment flags, and sandbox status.
 * @param {object} [options]
 * @param {string|null} [options.role=null]
 * @param {object} [options.sandboxStatus]
 * @param {object} [options.env=process.env]
 * @param {string|null} [options.sclangBinary]
 * @returns {object} Status map of available and unavailable runtimes
 */
function getRuntimeStatus({
  role = null,
  sandboxStatus = { ok: false },
  env = process.env,
  sclangBinary = findSclang()
} = {}) {
  const runtimes = {
    strudel: {
      name: "Strudel",
      available: true,
      execution: "browser",
      description: "Client-side browser mini-notation pattern engine"
    },
    tidalcycles: {
      name: "TidalCycles",
      available: false,
      reason: "not_installed",
      execution: "sandboxed_server"
    },
    sonicpi: {
      name: "Sonic Pi",
      available: false,
      reason: "not_installed",
      execution: "sandboxed_server"
    },
    sclang: {
      name: "SuperCollider sclang",
      available: false,
      execution: "sandboxed_server",
      gated: true
    }
  };

  // Evaluate SuperCollider sclang gating hierarchy:
  // 1. BRAHMA_ALLOW_SCLANG != 1 -> disabled_by_env
  // 2. role !== "human" -> human_role_required
  // 3. !sandboxStatus.ok -> sandbox_unavailable
  // 4. !sclangBinary -> not_installed
  if (env.BRAHMA_ALLOW_SCLANG !== "1") {
    runtimes.sclang.available = false;
    runtimes.sclang.reason = "disabled_by_env";
  } else if (role !== "human") {
    runtimes.sclang.available = false;
    runtimes.sclang.reason = "human_role_required";
  } else if (!sandboxStatus || !sandboxStatus.ok) {
    runtimes.sclang.available = false;
    runtimes.sclang.reason = "sandbox_unavailable";
  } else if (!sclangBinary) {
    runtimes.sclang.available = false;
    runtimes.sclang.reason = "not_installed";
  } else {
    runtimes.sclang.available = true;
    runtimes.sclang.binary = sclangBinary;
    runtimes.sclang.mode = "headless";
  }

  return runtimes;
}

/**
 * Headless sandboxed evaluation of SuperCollider sclang code.
 * @param {object} options
 * @param {string} options.code SuperCollider code string
 * @param {number} [options.timeoutMs=10000]
 * @param {string|null} [options.sclangPath]
 * @param {object} [options.env=process.env]
 * @returns {Promise<{ok: boolean, exitCode: number|null, signal: string|null, reason: string, stdout: string, stderr: string}>}
 */
async function executeSclang({
  code,
  timeoutMs = 10000,
  sclangPath = findSclang(),
  env = process.env
} = {}) {
  if (env.BRAHMA_ALLOW_SCLANG !== "1") {
    throw Object.assign(new Error("sclang execution disabled: BRAHMA_ALLOW_SCLANG != 1"), { code: "sclang_disabled" });
  }
  if (!sclangPath) {
    throw Object.assign(new Error("sclang binary not installed"), { code: "sclang_not_installed" });
  }
  const b = sandbox.backend();
  if (!b) {
    throw Object.assign(new Error("sandbox backend unavailable"), { code: "sandbox_unavailable" });
  }

  const scratch = sandbox.makeScratch();
  const scriptFile = path.join(scratch, "headless_eval.scd");

  // Wrap script to execute cleanly in headless sclang and exit with 0 or report error and exit 1.
  // The result is printed: an eval whose value cannot be observed is not verifiable,
  // and the API returns stdout as the answer.
  const wrappedCode = `
try {
  (
    ${code}
  ).postln;
  0.exit;
} { |err|
  err.reportError;
  1.exit;
};
`;
  fs.writeFileSync(scriptFile, wrappedCode, { mode: 0o600 });

  const spec = sandbox.sclangRuntimeSpec(sclangPath);
  const profile = sandbox.buildProfile({
    ...spec,
    readFiles: [scriptFile],
    scratch,
    udpPort: 57120 // SuperCollider engine port
  });

  let stdout = "";
  let stderr = "";

  const handle = sandbox.launch({
    cmd: spec.execs[0],
    args: [scriptFile],
    profile,
    scratch,
    limits: { wallMs: timeoutMs, outputBytes: 256 * 1024 },
    onStdout: (s) => { stdout += s; },
    onStderr: (s) => { stderr += s; },
  });

  const res = await handle.done;
  return {
    ok: res.code === 0,
    exitCode: res.code,
    signal: res.signal,
    reason: res.reason,
    stdout,
    stderr
  };
}

module.exports = {
  findSclang,
  getRuntimeStatus,
  executeSclang
};
