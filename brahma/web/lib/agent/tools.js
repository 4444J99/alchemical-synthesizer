"use strict";
/**
 * tools.js — the operations an approved proposal may invoke.
 *
 * Every tool declares whether it needs human approval. Read-only tools do not;
 * anything that writes a file or makes sound does. `run` returns plain data so the
 * result can be stored on the approval record and shown to a human afterwards.
 */

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const crypto = require("node:crypto");

const { validateEvents } = require("./providers");

function defaultExecFile(file, args, opts = {}) {
  const { spawn } = require("node:child_process");
  const { signal, timeout = 300000, maxBuffer = 8 * 1024 * 1024, ...options } = opts;
  let child;
  const promise = new Promise((resolve, reject) => {
    let timer;
    let failure = null;
    let bytes = 0;
    const stdout = [];
    const stderr = [];
    const abortError = () => Object.assign(new Error(
      signal && signal.reason instanceof Error ? signal.reason.message : "execution aborted"
    ), { name: "AbortError", code: "ABORT_ERR" });
    if (signal && signal.aborted) { reject(abortError()); return; }

    // A render shell spawns sclang, scsynth and watchdogs. Terminate their shared
    // process group; killing only the shell leaves those processes running.
    const killTree = () => {
      if (!child || !child.pid) return;
      try {
        if (process.platform === "win32") child.kill("SIGKILL");
        else process.kill(-child.pid, "SIGKILL");
      } catch (_) { /* process group already gone */ }
    };
    const abort = () => { failure = abortError(); killTree(); };
    // execFile does not forward `detached` to spawn, so use spawn explicitly.
    const env = { ...(options.env || process.env) };
    if (process.platform !== "win32") env.BRAHMA_SUPERVISED_PROCESS_GROUP = "1";
    else delete env.BRAHMA_SUPERVISED_PROCESS_GROUP;
    child = spawn(file, args, {
      ...options, env, detached: process.platform !== "win32", stdio: ["ignore", "pipe", "pipe"]
    });
    child.stop = abort;
    const capture = (chunks) => (chunk) => {
      if (failure) return;
      bytes += chunk.length;
      if (bytes > maxBuffer) {
        failure = Object.assign(new Error(`${path.basename(file)} output exceeded ${maxBuffer} bytes`), {
          code: "ERR_CHILD_PROCESS_STDIO_MAXBUFFER"
        });
        killTree();
        return;
      }
      chunks.push(chunk);
    };
    child.stdout.on("data", capture(stdout));
    child.stderr.on("data", capture(stderr));
    child.once("error", (err) => { failure = err; });
    child.once("close", (code, exitSignal) => {
      clearTimeout(timer);
      if (signal) signal.removeEventListener("abort", abort);
      if (failure) { reject(failure); return; }
      const out = Buffer.concat(stdout).toString("utf8");
      const err = Buffer.concat(stderr).toString("utf8");
      if (code !== 0) {
        const detail = (err || out).split("\n").slice(-8).join("\n");
        reject(new Error(`${path.basename(file)} failed: ${exitSignal || `exit ${code}`}${detail ? `\n${detail}` : ""}`));
        return;
      }
      resolve({ stdout: out, stderr: err });
    });
    // Also reap descendants after ordinary failure, output overflow, or a
    // wrapper that exits without waiting for its own subprocesses.
    child.once("exit", killTree);
    if (signal) signal.addEventListener("abort", abort, { once: true });
    timer = setTimeout(() => {
      failure = Object.assign(new Error(`${path.basename(file)} timed out after ${timeout}ms`), { code: "ETIMEDOUT" });
      killTree();
    }, timeout);
  });
  promise.child = child;
  return promise;
}

function createTools({ repoRoot, execFile = defaultExecFile, scratchRoot, engineHealth, now = () => Date.now() } = {}) {
  if (!repoRoot) throw new Error("createTools requires repoRoot");

  const scratch = scratchRoot || path.join(os.tmpdir(), "brahma-agent");

  function toolError(code, message) {
    const err = new Error(message);
    err.code = code;
    return err;
  }

  const tools = {
    render_pattern: {
      name: "render_pattern",
      approval: "required",
      description: "Render note events to a WAV with the NRT pattern voice, then measure it.",
      async run({ events, duration, label } = {}, { signal } = {}) {
        const valid = validateEvents(events);
        if (!valid) throw toolError("bad_events", "render_pattern requires valid note events");

        fs.mkdirSync(scratch, { recursive: true });
        const id = crypto.randomBytes(5).toString("hex");
        const safeLabel = String(label || "pattern").replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 40);

        const scorePath = path.join(scratch, `${safeLabel}-${id}.json`);
        const wavPath = path.join(scratch, `${safeLabel}-${id}.wav`);
        const summaryPath = path.join(scratch, `${safeLabel}-${id}.summary.json`);

        fs.writeFileSync(scorePath, JSON.stringify({ events: valid }, null, 2), "utf8");

        const lastEnd = valid.reduce((m, e) => Math.max(m, e.time + e.dur), 0);
        const renderSecs = Number(duration) > 0 ? Number(duration) : Math.max(2, lastEnd + 1.5);

        await execFile("bash", [path.join(repoRoot, "forge/render-pattern.sh"), scorePath, wavPath, String(renderSecs)], { signal });
        if (signal) signal.throwIfAborted();

        if (!fs.existsSync(wavPath) || fs.statSync(wavPath).size === 0) {
          throw toolError("render_failed", "render produced no audio file");
        }

        await execFile("python3", [
          path.join(repoRoot, "forge/analyze_audio.py"),
          wavPath,
          "--summary-json",
          summaryPath
        ], { signal });
        if (signal) signal.throwIfAborted();

        const summary = JSON.parse(fs.readFileSync(summaryPath, "utf8"));

        return {
          wavPath,
          scorePath,
          summaryPath,
          events: valid.length,
          renderSeconds: renderSecs,
          // The measurement is reported as measured. It is not a claim that anyone
          // heard the result; a human still has to listen.
          measured: summary
        };
      }
    },

    analyze_audio: {
      name: "analyze_audio",
      approval: "none",
      description: "Measure an existing audio file (read-only).",
      async run({ wavPath } = {}, { signal } = {}) {
        if (!wavPath || !fs.existsSync(wavPath)) throw toolError("no_such_file", `no such audio file: ${wavPath}`);
        fs.mkdirSync(scratch, { recursive: true });
        const summaryPath = path.join(scratch, `analyze-${crypto.randomBytes(5).toString("hex")}.json`);

        await execFile("python3", [
          path.join(repoRoot, "forge/analyze_audio.py"),
          wavPath,
          "--summary-json",
          summaryPath
        ], { signal });
        if (signal) signal.throwIfAborted();
        return { wavPath, summaryPath, measured: JSON.parse(fs.readFileSync(summaryPath, "utf8")) };
      }
    },

    engine_status: {
      name: "engine_status",
      approval: "none",
      description: "Report SuperCollider gateway health (read-only).",
      async run() {
        return {
          engine: typeof engineHealth === "function" ? engineHealth() : { ok: false, reason: "no_engine_probe" },
          checkedAt: new Date(now()).toISOString()
        };
      }
    }
  };

  function get(name) {
    return tools[String(name)] || null;
  }

  async function run(name, args, { signal } = {}) {
    const tool = get(name);
    if (!tool) throw toolError("unknown_tool", `Unknown tool ${name}`);

    if (signal) signal.throwIfAborted();
    const result = await tool.run(args || {}, { signal });
    if (signal) signal.throwIfAborted();
    return result;
  }

  function catalogue() {
    return Object.values(tools).map((t) => ({
      name: t.name,
      approval: t.approval,
      description: t.description
    }));
  }

  return { get, run, catalogue, scratch };
}

module.exports = { createTools, defaultExecFile };
