"use strict";
// Local, authenticated bridge to Forge's source-owned native render pipeline.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFile } = require("node:child_process");
const express = require("express");
const ROOT = path.resolve(__dirname, "../../..");
const SPECS = require(path.join(ROOT, "forge/native-controls.json"));
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const MAX_AUDIO = 44 + 30 * 44100 * 4;
function fail(message, status = 400) { const error = new Error(message); error.status = status; throw error; }
function admitAudio(audio) {
  if (!audio || typeof audio.data !== "string" || audio.data.length > Math.ceil(MAX_AUDIO / 3) * 4 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(audio.data)) fail("Invalid PCM WAV encoding");
  const bytes = Buffer.from(audio.data, "base64");
  if (bytes.length < 44 || bytes.length > MAX_AUDIO || bytes.toString("base64") !== audio.data ||
      bytes.toString("ascii", 0, 4) !== "RIFF" || bytes.toString("ascii", 8, 16) !== "WAVEfmt " ||
      bytes.readUInt32LE(4) !== bytes.length - 8 || bytes.readUInt32LE(16) !== 16 ||
      bytes.readUInt16LE(20) !== 1 || bytes.readUInt16LE(22) !== 2 || bytes.readUInt32LE(24) !== 44100 ||
      bytes.readUInt32LE(28) !== 176400 || bytes.readUInt16LE(32) !== 4 || bytes.readUInt16LE(34) !== 16 ||
      bytes.toString("ascii", 36, 40) !== "data" || bytes.readUInt32LE(40) !== bytes.length - 44 ||
      (bytes.length - 44) % 4) fail("Use stereo 44.1 kHz PCM16 WAV");
  const duration = (bytes.length - 44) / 176400;
  if (duration < 1 || duration > 30) fail("Native sounds must be between 1 and 30 seconds");
  const hash = sha(bytes);
  if (audio.sha256 !== hash) fail("Source audio hash mismatch");
  return { bytes, sha256: hash, duration };
}
function validateParams(module, params = {}) {
  if (!params || typeof params !== "object" || Array.isArray(params)) fail("Invalid native controls");
  const spec = SPECS[module] || {};
  const clean = {};
  for (const [key, value] of Object.entries(params)) {
    if (!Object.hasOwn(spec, key)) fail("Unsupported native control: " + key);
    const [, min, max, step] = spec[key];
    if (!Number.isFinite(value) || value < min || value > max || (step === 1 && !Number.isInteger(value))) fail("Native control outside range: " + key);
    clean[key] = value;
  }
  return clean;
}
function command(args, options = {}, onChild = () => {}) {
  return new Promise((resolve, reject) => {
    const child = execFile(process.env.BRAHMA_PYTHON || "python3", args,
      { cwd: ROOT, maxBuffer: 2 * 1024 * 1024, ...options }, (error, stdout, stderr) => {
        clearTimeout(deadline); clearTimeout(kill);
        if (error) {
          const failure = new Error("Native render failed; private diagnostic log retained");
          failure.diagnostic = String(stdout || "") + String(stderr || ""); reject(failure);
        }
        else resolve(stdout);
      });
    let kill;
    const terminate = () => { child.kill("SIGTERM"); kill = setTimeout(() => child.kill("SIGKILL"), 3000); };
    const deadline = setTimeout(terminate, 150000);
    onChild({ terminate });
  });
}
function loadCatalogue() {
  return command([path.join(ROOT, "forge/assimilate.py"), "--catalogue"]).then(JSON.parse);
}
async function runNative(directory, request, donor, onChild) {
  const args = [path.join(ROOT, "forge/assimilate.py"), path.join(directory, "source.wav"),
    "--start", "0", "--duration", String(donor.duration), "--module", request.module,
    "--out", directory, "--deadline", "120"];
  for (const [key, value] of Object.entries(request.params)) args.push("--param", key + "=" + value);
  const output = await command(args, {}, onChild).catch(error => {
    fs.writeFileSync(path.join(directory, "service-error.txt"), error.message + "\n" + (error.diagnostic || "")); throw error;
  });
  fs.writeFileSync(path.join(directory, "service.log"), output);
  const result = JSON.parse(output.trim().split("\n").at(-1));
  const rendered = path.resolve(result.directory);
  if (!rendered.startsWith(directory + path.sep)) fail("Unexpected native result path", 500);
  return rendered;
}
function createNativeService({ root = path.join(ROOT, "forge/out/instrument"), catalogue = loadCatalogue,
  render = runNative, maxJobs = 64 } = {}) {
  const jobs = new Map(); let active = null, closed = false;
  let catalogPromise;
  const getCatalogue = () => catalogPromise || (catalogPromise = Promise.resolve().then(catalogue).catch(error => {
    catalogPromise = null; throw error;
  }));
  function view(job) {
    return { id: job.id, state: job.state, module: job.module, params: job.params,
      sourceSha256: job.sourceSha256, error: job.error || null, result: job.result || null };
  }
  async function start(body) {
    if (closed) fail("Native service is closed", 503);
    const catalog = await getCatalogue();
    if (closed) fail("Native service is closed", 503);
    if (active) fail("A native sound is already rendering", 409);
    if (jobs.size >= maxJobs) fail("Native session render budget reached; restart the local server for a new session", 429);
    const module = catalog.find(item => item.name === body.module);
    if (!module || module.role === "infrastructure" || !(module.audio_outputs.length || module.control_outputs.length)) fail("Native module requires its owning patch");
    const params = validateParams(module.name, body.params);
    const donor = admitAudio(body.audio);
    fs.mkdirSync(root, { recursive: true, mode: 0o700 });
    const space = fs.statfsSync(root);
    if (space.bavail * space.bsize < 1024 ** 3) fail("Native render requires 1 GiB of free space", 507);
    const id = "native_" + crypto.randomBytes(12).toString("hex"), directory = path.join(fs.realpathSync(root), id);
    fs.mkdirSync(directory, { mode: 0o700 });
    fs.writeFileSync(path.join(directory, "source.wav"), donor.bytes, { mode: 0o600 });
    fs.writeFileSync(path.join(directory, "request.json"), JSON.stringify({ module: module.name, params, sha256: donor.sha256 }), { mode: 0o600 });
    const job = { id, module: module.name, params, directory, state: "running", sourceSha256: donor.sha256 };
    jobs.set(id, job); active = id;
    job.promise = Promise.resolve().then(() => render(directory, job, donor, child => { job.child = child; if (job.cancelled) child.terminate(); }))
      .then(rendered => {
        if (job.cancelled) return;
        const manifest = JSON.parse(fs.readFileSync(path.join(rendered, "manifest.json")));
        const item = manifest.modules.find(item => item.name === job.module);
        if (!item || item.status !== "rendered" || item.render_exit_code !== 0 || manifest.compile_exit_code !== 0 ||
            manifest.donor.sha256 !== donor.sha256 || item.output !== job.module + ".wav") fail("Native result did not pass validation", 500);
        const output = path.join(rendered, item.output), bytes = fs.readFileSync(output);
        if (sha(bytes) !== item.output_sha256) fail("Native result hash mismatch", 500);
        if (sha(fs.readFileSync(path.join(directory, "source.wav"))) !== donor.sha256) fail("Native source changed", 500);
        job.output = output;
        job.result = { sha256: item.output_sha256, duration: item.duration_seconds,
          definitionSha256: item.definition_sha256, rackSha256: manifest.native_rack_sha256,
          measurement: { peakDbfs: item.peak_dbfs, rmsDbfs: item.rms_dbfs } };
        job.state = "completed";
      }).catch(error => { if (!job.cancelled) { job.state = "failed"; job.error = error.message; } })
      .finally(() => { job.child = null; if (active === id) active = null; });
    return view(job);
  }
  function cancel(id) {
    const job = jobs.get(id);
    if (!job) fail("Unknown native render", 404);
    if (job.state === "running") { job.cancelled = true; job.state = "cancelled"; if (job.child) job.child.terminate(); }
    return view(job);
  }
  return { catalogue: getCatalogue, start, cancel, get: id => jobs.has(id) ? view(jobs.get(id)) : null,
    output(id) { const job = jobs.get(id); if (!job || job.state !== "completed") fail("Native audio is not ready", 404); return job.output; },
    async drain() { await Promise.all([...jobs.values()].map(job => job.promise)); },
    close() { closed = true; for (const job of jobs.values()) if (job.state === "running") cancel(job.id); } };
}
function createNativeSamplesRouter({ auth, service = createNativeService() }) {
  const router = express.Router();
  router.use((req, res, next) => {
    res.setHeader("Cache-Control", "no-store");
    if (!auth.isLoopback(req) || !auth.originOk(req)) return res.status(403).json({ error: "Loopback and trusted Origin required" });
    if (auth.roleOf(req) !== "human") return res.status(403).json({ error: "Connect the local instrument session first" });
    next();
  });
  router.use(express.json({ limit: "8mb" }));
  router.get("/catalogue", async (req, res, next) => {
    try { res.json({ modules: await service.catalogue() }); } catch (error) { next(error); }
  });
  router.post("/jobs", async (req, res, next) => {
    try { res.status(202).json(await service.start(req.body || {})); } catch (error) { next(error); }
  });
  router.get("/jobs/:id", (req, res) => {
    const job = service.get(req.params.id); if (!job) return res.status(404).json({ error: "Unknown native render" }); res.json(job);
  });
  router.delete("/jobs/:id", (req, res, next) => { try { res.json(service.cancel(req.params.id)); } catch (error) { next(error); } });
  router.get("/jobs/:id/audio", (req, res, next) => {
    try {
      const output = service.output(req.params.id);
      res.type("audio/wav").sendFile(path.basename(output), { root: path.dirname(output), dotfiles: "deny" });
    } catch (error) { next(error); }
  });
  router.use((error, req, res, next) => res.status(error.status || 503).json({ error: error.message }));
  router.service = service;
  return router;
}
module.exports = { admitAudio, validateParams, createNativeService, createNativeSamplesRouter };
