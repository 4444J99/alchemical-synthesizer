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
  const { execFile } = require("node:child_process");
  return new Promise((resolve, reject) => {
    execFile(
      file,
      args,
      { timeout: opts.timeout || 300000, maxBuffer: 8 * 1024 * 1024, ...opts },
      (err, stdout, stderr) => {
        if (err) {
          const detail = (stderr || stdout || "").split("\n").slice(-8).join("\n");
          reject(new Error(`${path.basename(file)} failed: ${err.message}${detail ? `\n${detail}` : ""}`));
          return;
        }
        resolve({ stdout, stderr });
      }
    );
  });
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
      async run({ events, duration, label } = {}) {
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

        await execFile("bash", [path.join(repoRoot, "forge/render-pattern.sh"), scorePath, wavPath, String(renderSecs)]);

        if (!fs.existsSync(wavPath) || fs.statSync(wavPath).size === 0) {
          throw toolError("render_failed", "render produced no audio file");
        }

        await execFile("python3", [
          path.join(repoRoot, "forge/analyze_audio.py"),
          wavPath,
          "--summary-json",
          summaryPath
        ]);

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
      async run({ wavPath } = {}) {
        if (!wavPath || !fs.existsSync(wavPath)) throw toolError("no_such_file", `no such audio file: ${wavPath}`);
        fs.mkdirSync(scratch, { recursive: true });
        const summaryPath = path.join(scratch, `analyze-${crypto.randomBytes(5).toString("hex")}.json`);

        await execFile("python3", [
          path.join(repoRoot, "forge/analyze_audio.py"),
          wavPath,
          "--summary-json",
          summaryPath
        ]);
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

  async function run(name, args) {
    const tool = get(name);
    if (!tool) throw toolError("unknown_tool", `Unknown tool ${name}`);
    return tool.run(args || {});
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
