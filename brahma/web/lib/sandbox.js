"use strict";
/**
 * sandbox.js — OS-level isolation for server-side language runtimes.
 *
 * Spawning a child process is not isolation. Every runtime is launched through
 * here, which layers:
 *   - Seatbelt (/usr/bin/sandbox-exec) profile: deny default; read only the
 *     runtime's install roots; write only a fresh 0700 scratch directory; no
 *     network except UDP to the one engine ingress port; no shell on the exec
 *     allow-list.
 *   - scrubbed environment, no inherited fds beyond stdio;
 *   - ulimit wrapper (applied *outside* the sandbox, inherited across exec);
 *   - a new session leader, killed by process group; wall-clock + output caps.
 *   - FAIL CLOSED: selfTest() proves the profile really denies writes outside
 *     scratch, reading a canary secret, TCP, spawning a shell and other UDP
 *     ports. If any attempt succeeds or the backend is missing, the runtime is
 *     reported unavailable. There is no unsandboxed fallback and no flag for one.
 *
 * Honest limits: sandbox-exec is deprecated by Apple (but present and working);
 * Seatbelt is an OS boundary, not a VM; UDP bind on ephemeral ports is allowed
 * because UDP send needs it, so the only outbound path is the engine port.
 */

const fs = require("fs");
const os = require("os");
const net = require("net");
const path = require("path");
const crypto = require("crypto");
const { spawn, execFileSync } = require("child_process");

const SANDBOX_EXEC = "/usr/bin/sandbox-exec";
const DEFAULT_LIMITS = { cpuSec: 120, openFiles: 256, procs: 64, wallMs: 10 * 60 * 1000, outputBytes: 256 * 1024 };

function backend() {
  if (process.platform === "darwin" && fs.existsSync(SANDBOX_EXEC)) return "seatbelt";
  return null; // Linux bwrap backend is a declared follow-up; no silent fallback.
}

function realpaths(list) {
  const out = new Set();
  for (const p of list) {
    if (!p) continue;
    out.add(p);
    try { out.add(fs.realpathSync(p)); } catch (_) { /* absent path: keep literal only */ }
  }
  return [...out];
}

const q = (s) => JSON.stringify(String(s)); // Seatbelt string literals are double-quoted

/**
 * Generate a Seatbelt profile.
 * @param {object} o
 * @param {string[]} o.readRoots   directories the runtime may read (install roots, libs)
 * @param {string[]} o.readFiles   individual files the runtime may read (entry scripts)
 * @param {string[]} o.execs       the only binaries that may be exec'd
 * @param {string}   o.scratch     the only writable directory
 * @param {number}   o.udpPort     the only UDP destination port
 * @param {boolean}  [o.allowFork] runtimes that fork helpers (default false)
 */
function buildProfile({ readRoots = [], readFiles = [], execs = [], scratch, udpPort, inboundUdpPort = udpPort, allowFork = false }) {
  const lines = [
    "(version 1)",
    "(deny default)",
    "(allow sysctl-read)",
    "(allow file-read-metadata)",
    "(allow signal (target self))",
    "(allow mach-lookup)",
    ...(allowFork ? ["(allow process-fork)"] : ["(allow process-fork)"]), // node needs fork for workers; exec is what is restricted
    `(allow process-exec ${realpaths(execs).map((p) => `(literal ${q(p)})`).join(" ")})`,
    `(allow file-read* (subpath "/usr/lib") (subpath "/System") (subpath "/dev") (subpath "/private/var/db/timezone") (subpath "/Library/Preferences/Logging") (subpath "/System/Volumes/Preboot") (literal "/") (literal "/private") (literal "/tmp") (literal "/opt") (literal "/opt/homebrew")${
      realpaths(readRoots).map((p) => ` (subpath ${q(p)})`).join("")
    })`,
  ];
  const files = realpaths(readFiles);
  if (files.length) lines.push(`(allow file-read* ${files.map((p) => `(literal ${q(p)})`).join(" ")})`);
  const sc = realpaths([scratch]);
  lines.push(`(allow file-read* file-write* ${sc.map((p) => `(subpath ${q(p)})`).join(" ")})`);
  lines.push('(allow file-write* (literal "/dev/null"))');
  lines.push("(deny network*)");
  lines.push('(allow network-bind (local udp "*:*"))');
  // sclang opens its own inbound UDP port at startup and dies noisily without this:
  // binding is not receiving, and Seatbelt treats them as separate operations.
  lines.push(`(allow network-inbound (local udp "*:${Number(inboundUdpPort)}"))`);
  lines.push(`(allow network-outbound (remote udp "localhost:${Number(udpPort)}"))`);
  return lines.join("\n") + "\n";
}

/** Create a fresh 0700 scratch directory. */
function makeScratch(base = os.tmpdir()) {
  const dir = fs.mkdtempSync(path.join(fs.realpathSync(base), "brahma-sbx-"));
  fs.chmodSync(dir, 0o700);
  return dir;
}

function rmScratch(dir) { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) { /* best effort */ } }

/** Standard read roots for a Node-based runtime on this machine (Homebrew layout). */
function nodeRuntimeSpec() {
  const real = fs.realpathSync(process.execPath);
  return {
    execs: [real],
    readRoots: ["/opt/homebrew/opt", "/opt/homebrew/lib", "/opt/homebrew/Cellar", "/opt/homebrew/etc/openssl@4", "/opt/homebrew/etc/openssl@3", path.dirname(path.dirname(real))],
  };
}

/** Standard read roots and execution spec for SuperCollider sclang. */
function sclangRuntimeSpec(sclangPath) {
  const real = fs.realpathSync(sclangPath);
  const appDir = real.includes(".app")
    ? real.slice(0, real.indexOf(".app") + 4)
    : path.dirname(path.dirname(real));
  return {
    execs: [real],
    readRoots: [
      appDir,
      "/opt/homebrew",
      "/usr/local",
      "/Library/Application Support/SuperCollider",
      path.join(os.homedir(), "Library/Application Support/SuperCollider"),
      path.join(__dirname, "..", "..", "sc")
    ],
  };
}

function ulimitPrefix(l) {
  return `ulimit -t ${Number(l.cpuSec)}; ulimit -n ${Number(l.openFiles)}; ulimit -u ${Number(l.procs)}; exec "$@"`;
}

/**
 * Launch a command inside the sandbox.
 * @returns {{pid:number, kill:(sig?:string)=>void, done:Promise<{code:number|null,signal:string|null,reason:string}>, scratch:string}}
 */
function launch({ cmd, args = [], profile, scratch, env = {}, limits = {}, onStdout, onStderr, cwd, keepScratch = false }) {
  const b = backend();
  if (!b) throw Object.assign(new Error("no sandbox backend available"), { code: "sandbox_unavailable" });
  const lim = { ...DEFAULT_LIMITS, ...limits };
  const profileFile = path.join(os.tmpdir(), `brahma-prof-${crypto.randomBytes(6).toString("hex")}.sb`);
  fs.writeFileSync(profileFile, profile, { mode: 0o600 });
  const cleanEnv = { PATH: "/usr/bin:/bin", HOME: scratch, TMPDIR: scratch, LANG: "C", ...env };

  // ulimit is applied by an *outer* shell, outside the sandbox; limits survive exec.
  const child = spawn("/bin/sh", ["-c", ulimitPrefix(lim), "brahma-sbx", SANDBOX_EXEC, "-f", profileFile, cmd, ...args], {
    env: cleanEnv,
    cwd: cwd || scratch,
    detached: true, // new session + process group, so the whole tree is killable
    stdio: ["ignore", "pipe", "pipe"],
  });

  let bytes = 0;
  let reason = "exit";
  let killed = false;
  const kill = (sig = "SIGTERM") => {
    if (killed && sig !== "SIGKILL") return;
    killed = true;
    try { process.kill(-child.pid, sig); } catch (_) { /* group already gone */ }
  };
  const cap = (fn) => (chunk) => {
    bytes += chunk.length;
    if (bytes > lim.outputBytes) { reason = "output_limit"; kill("SIGKILL"); return; }
    if (fn) fn(chunk.toString("utf8"));
  };
  child.stdout.on("data", cap(onStdout));
  child.stderr.on("data", cap(onStderr));
  const timer = setTimeout(() => { reason = "wall_clock_timeout"; kill("SIGTERM"); setTimeout(() => kill("SIGKILL"), 1500).unref(); }, lim.wallMs);

  const done = new Promise((resolve) => {
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      try { fs.rmSync(profileFile, { force: true }); } catch (_) {}
      if (!keepScratch) rmScratch(scratch);
      if (killed && reason === "exit") reason = "killed";
      resolve({ code, signal, reason });
    });
    child.on("error", (e) => { clearTimeout(timer); resolve({ code: null, signal: null, reason: "spawn_error:" + e.code }); });
  });
  return { pid: child.pid, kill, done, scratch };
}

/**
 * Prove the sandbox denies what it must. Runs a Node probe inside a fresh profile.
 * @returns {Promise<{ok:boolean, backend:string|null, checks:object, reason?:string}>}
 */
async function selfTest({ udpPort = 57130 } = {}) {
  const b = backend();
  if (!b) return { ok: false, backend: null, checks: {}, reason: "no_backend" };

  const outsideDir = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), "brahma-canary-"));
  const canary = path.join(outsideDir, "secret.txt");
  fs.writeFileSync(canary, "canary-secret");

  // A local TCP listener the probe must NOT be able to reach.
  const srv = net.createServer((s) => s.destroy());
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const tcpPort = srv.address().port;

  const scratch = makeScratch();
  const probe = path.join(scratch, "probe.js");
  fs.writeFileSync(probe, `
const fs=require("fs"),net=require("net"),dgram=require("dgram"),cp=require("child_process"),path=require("path");
const r={};const t=(k,f)=>{try{f();r[k]="allowed"}catch(e){r[k]="denied"}};
t("write_scratch",()=>fs.writeFileSync(path.join(${q(scratch)},"ok"),"x"));
t("write_outside",()=>fs.writeFileSync(path.join(${q(outsideDir)},"w"),"x"));
t("read_canary",()=>fs.readFileSync(${q(canary)}));
t("exec_shell",()=>cp.execFileSync("/bin/sh",["-c","true"]));
let n=0;const fin=()=>{if(++n===3)console.log("RESULT "+JSON.stringify(r))};
const c=net.connect({host:"127.0.0.1",port:${tcpPort},timeout:1500});
c.on("connect",()=>{r.tcp="allowed";c.destroy();fin()});c.on("error",()=>{r.tcp="denied";fin()});c.on("timeout",()=>{r.tcp="denied";c.destroy();fin()});
// OSC address string (24 bytes) + empty type-tag string (4 bytes).
// Raw non-OSC bytes can abort sclang 3.14.x, including an already-running IDE.
const packet=Buffer.alloc(28);packet.write("/brahma/sandbox/probe");packet[24]=44;
const u=(k,p)=>{const s=dgram.createSocket("udp4");s.send(packet,p,"127.0.0.1",(e)=>{r[k]=e?"denied":"allowed";s.close();fin()})};
u("udp_other",9);u("udp_engine",${Number(udpPort)});
`);
  const spec = nodeRuntimeSpec();
  const profile = buildProfile({ ...spec, readFiles: [probe], scratch, udpPort });
  let out = "";
  let res;
  try {
    const h = launch({ cmd: spec.execs[0], args: [probe], profile, scratch, onStdout: (s) => { out += s; }, limits: { wallMs: 15000 }, keepScratch: true });
    res = await h.done;
  } finally {
    srv.close();
    rmScratch(scratch);
    rmScratch(outsideDir);
  }
  const m = out.match(/RESULT (\{.*\})/);
  if (!m) return { ok: false, backend: b, checks: {}, reason: "probe_did_not_run:" + res.reason };
  const checks = JSON.parse(m[1]);
  const expected = { write_scratch: "allowed", write_outside: "denied", read_canary: "denied", exec_shell: "denied", tcp: "denied", udp_other: "denied", udp_engine: "allowed" };
  const bad = Object.keys(expected).filter((k) => checks[k] !== expected[k]);
  return { ok: bad.length === 0, backend: b, checks, reason: bad.length ? "self_test_failed:" + bad.join(",") : undefined };
}

module.exports = { backend, buildProfile, makeScratch, rmScratch, launch, selfTest, nodeRuntimeSpec, sclangRuntimeSpec, DEFAULT_LIMITS };
