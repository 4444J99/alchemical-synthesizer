"use strict";
/**
 * engine.js — Bridge to the SuperCollider Brahma engine over OSC.
 *
 * The Foundry must run whether or not a live SC server is present (so it is
 * deployable to the cloud today, with the audio engine local to performers).
 * - When SC is observed, organism telemetry flows in on 57122 and commands go
 *   out on 57120, exactly matching the existing brahma/web bridge topology.
 * - renderSpecimen dispatches a render request to the live engine when one is
 *   observed, and the specimen stays pending until the engine reports
 *   completion. A specimen is only a rendered artifact once the completion
 *   receipt names a file that exists under FOUNDRY_DATA_DIR and whose WAV
 *   header measures real audio; until then it is simulated, with no audio
 *   claim. Dispatch is not completion, and telemetry is not completion.
 *   (Issue #96.)
 */

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { collection, logEvent, DATA_DIR } = require("./store");
const { upsertFromRegistry, getModule, seedTraitMap } = require("./catalog");

const OSC_RECV_PORT = Number(process.env.OSC_RECV_PORT || 57122);
const OSC_SEND_PORT = Number(process.env.OSC_SEND_PORT || 57120);
const SC_HOST = process.env.SC_HOST || "127.0.0.1";
const TELEMETRY_TTL_MS = 2000;
// A render that never reports back fails closed after this window. Tests set
// FOUNDRY_RENDER_TIMEOUT_MS small; production default is 30s.
const RENDER_TIMEOUT_MS = Number(process.env.FOUNDRY_RENDER_TIMEOUT_MS || 30000);
// Renders are short specimens; bound the request so a bad duration cannot ask
// the engine for an unbounded NRT job. The SC receiver enforces the same bound.
const RENDER_MAX_DURATION_SEC = 60;
const RENDER_MAX_FILE_BYTES = 256 * 1024 * 1024;

const specimens = () => collection("specimens");

// Live organism telemetry keyed by entityId.
const organisms = new Map();
let lastTelemetryAt = null;
let udpPort = null;
let sendPort = null;

// Pending renders keyed by renderId (which is the specimen id): the specimen
// the render belongs to, plus the timeout that fails it closed.
const pendingRenders = new Map();

function start() {
  let osc;
  try { osc = require("osc"); } catch (e) {
    console.warn("[engine] 'osc' not installed — engine bridge disabled, simulation only");
    return;
  }
  try {
    udpPort = new osc.UDPPort({ localAddress: "0.0.0.0", localPort: OSC_RECV_PORT, metadata: true });
    sendPort = new osc.UDPPort({ localAddress: "0.0.0.0", localPort: 0, remoteAddress: SC_HOST, remotePort: OSC_SEND_PORT, metadata: true });

    udpPort.on("ready", () => console.log(`[engine] OSC listener ready :${OSC_RECV_PORT}`));
    udpPort.on("close", () => {
      lastTelemetryAt = null;
      organisms.clear();
      failAllPendingRenders("transport closed");
    });
    udpPort.on("error", (e) => console.warn("[engine] OSC error:", e.message));
    udpPort.on("message", onOscMessage);
    sendPort.on("ready", () => console.log(`[engine] OSC sender → ${SC_HOST}:${OSC_SEND_PORT}`));
    sendPort.on("error", () => {});

    udpPort.open();
    sendPort.open();
  } catch (e) {
    console.warn("[engine] failed to bind OSC ports (likely already in use):", e.message);
  }
}

function onOscMessage(msg) {
  if (!msg || !Array.isArray(msg.args)) return;
  const a = msg.args;
  const val = (i) => (a[i] && a[i].value !== undefined ? a[i].value : a[i]);

  if (msg.address === "/brahma/organism/update") {
    const id = val(0);
    const type = val(1);
    const coherence = val(2);
    const entropy = val(3);
    const validId = (typeof id === "string" && id.trim().length > 0) ||
      (Number.isSafeInteger(id) && id >= 0);
    if (!validId || typeof type !== "string" || !type.trim() ||
        !Number.isFinite(coherence) || coherence < 0 || coherence > 1 ||
        !Number.isFinite(entropy) || entropy < 0) return;
    lastTelemetryAt = Date.now();
    organisms.set(id, {
      id, type, coherence, entropy, lastUpdate: lastTelemetryAt
    });
  } else if (msg.address === "/brahma/registry/module") {
    upsertFromRegistry({
      name: val(0), category: val(1), synthDef: val(2),
      numParams: val(3) || 0, numInstances: val(4) || 0, description: val(5) || ""
    });
  } else if (msg.address === "/brahma/foundry/render/done") {
    // Completion is a distinct message; organism telemetry never completes a
    // render. The renderId must match a pending render; anything else is a
    // stray or duplicate receipt and is ignored.
    const renderId = val(0);
    if (typeof renderId === "string" && renderId) completePendingRender(renderId);
  } else if (msg.address === "/brahma/foundry/render/failed") {
    const renderId = val(0);
    const reason = val(1);
    if (typeof renderId === "string" && renderId) {
      failPendingRender(renderId,
        typeof reason === "string" && reason ? reason : "engine reported failure");
    }
  }
}

/** Dispatch a command only with fresh telemetry; dispatch is not completion. */
function send(address, args = []) {
  if (!sendPort || !isOnline()) return false;
  try {
    sendPort.send({
      address,
      args: args.map((v) =>
        typeof v === "number"
          ? (Number.isInteger(v) ? { type: "i", value: v } : { type: "f", value: v })
          : { type: "s", value: String(v) })
    });
    return true;
  } catch (e) { return false; }
}

/** Decay stale organisms (mirrors the 2s web decay rule). */
function organismState() {
  const now = Date.now();
  for (const [id, o] of organisms) {
    if (now < o.lastUpdate || now - o.lastUpdate > TELEMETRY_TTL_MS) organisms.delete(id);
  }
  // A render pending on a peer that has gone stale can never complete: fail
  // it closed here instead of leaving it pending until its timeout.
  if (!isOnline()) failAllPendingRenders("peer stale");
  return [...organisms.values()];
}

/** Where a completed render must land: under the store dir, by renderId. */
function renderOutputPath(renderId) {
  return path.join(DATA_DIR, "specimens", `${renderId}.wav`);
}

/**
 * Measure a WAV file from its header (RIFF/WAVE, PCM): channels, sample rate,
 * frames and duration. Returns null for anything unmeasurable — missing file,
 * bad magic, non-PCM, missing fmt/data chunk, or zero frames. The completion
 * path trusts this measurement, never the peer's claim about the file.
 */
function measureWavFile(filePath) {
  let stat;
  try {
    stat = fs.statSync(filePath);
    if (!stat.isFile() || stat.size > RENDER_MAX_FILE_BYTES) return null;
  } catch { return null; }
  let buf;
  try { buf = fs.readFileSync(filePath); } catch { return null; }
  if (buf.length < 44) return null;
  if (buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WAVE") return null;
  let fmt = null;
  let dataSize = null;
  let offset = 12;
  while (offset + 8 <= buf.length) {
    const id = buf.toString("ascii", offset, offset + 4);
    const size = buf.readUInt32LE(offset + 4);
    const body = offset + 8;
    if (body + size > buf.length) return null;
    if (id === "fmt " && size >= 16) {
      const audioFormat = buf.readUInt16LE(body);
      fmt = {
        audioFormat,
        channels: buf.readUInt16LE(body + 2),
        sampleRate: buf.readUInt32LE(body + 4),
        blockAlign: buf.readUInt16LE(body + 12),
        bitsPerSample: buf.readUInt16LE(body + 14)
      };
    } else if (id === "data") {
      dataSize = size;
    }
    // Chunks are word-aligned; a trailing odd byte pads the next chunk.
    offset = body + size + (size % 2);
  }
  if (!fmt || dataSize === null) return null;
  if (fmt.audioFormat !== 1) return null; // PCM only; NRT writes int16 WAV
  if (!Number.isSafeInteger(fmt.channels) || fmt.channels < 1) return null;
  if (!Number.isSafeInteger(fmt.sampleRate) || fmt.sampleRate <= 0) return null;
  if (![8, 16, 24, 32].includes(fmt.bitsPerSample)) return null;
  if (!Number.isSafeInteger(fmt.blockAlign) || fmt.blockAlign <= 0) return null;
  const frames = Math.floor(dataSize / fmt.blockAlign);
  if (frames <= 0) return null;
  return {
    channels: fmt.channels,
    sampleRate: fmt.sampleRate,
    bitsPerSample: fmt.bitsPerSample,
    frames,
    durationSec: frames / fmt.sampleRate
  };
}

/** Fail one pending render closed. Returns false when nothing was pending. */
function failPendingRender(renderId, reason) {
  const pending = pendingRenders.get(renderId);
  if (!pending) return false;
  pendingRenders.delete(renderId);
  clearTimeout(pending.timer);
  const row = specimens().find((s) => s.id === pending.specimenId);
  if (row && row.renderState === "pending") {
    specimens().update((s) => s.id === pending.specimenId, { renderState: "failed" });
    logEvent("specimen.render_failed", `${pending.specimenId}:${reason}`);
  }
  return true;
}

function failAllPendingRenders(reason) {
  for (const renderId of [...pendingRenders.keys()]) failPendingRender(renderId, reason);
}

/**
 * Settle a pending render from the engine's completion receipt. The file is
 * located by the renderId under FOUNDRY_DATA_DIR — the peer's echoed path is
 * never trusted for the location — and must measure as real audio, or the
 * render fails closed and audioUrl stays null.
 */
function completePendingRender(renderId) {
  const pending = pendingRenders.get(renderId);
  if (!pending) return false;
  pendingRenders.delete(renderId);
  clearTimeout(pending.timer);
  const row = specimens().find((s) => s.id === pending.specimenId);
  if (!row || row.renderState !== "pending") return false;
  const measured = measureWavFile(renderOutputPath(renderId));
  if (!measured) {
    specimens().update((s) => s.id === pending.specimenId, { renderState: "failed" });
    logEvent("specimen.render_failed", `${pending.specimenId}:completion file missing or unmeasurable`);
    return false;
  }
  specimens().update((s) => s.id === pending.specimenId, {
    simulated: false,
    renderState: "complete",
    audioUrl: `${renderId}.wav`,
    durationSec: measured.durationSec,
    renderCompletedAt: new Date().toISOString()
  });
  logEvent("specimen.render_completed",
    `${pending.specimenId}:${measured.frames}f/${measured.durationSec}s/${measured.channels}ch`);
  return true;
}

/**
 * Create a specimen record. With no live engine it is a simulated record
 * (renderState "unavailable", audioUrl null). With a live engine the render
 * request is dispatched and the specimen is pending: it carries no audio
 * claim until the engine's completion receipt is verified against a measured
 * file. Ownership is supplied separately by the authenticated capability caller.
 */
function renderSpecimen({ module, title, creator, durationSec = 4 }, { ownerEmail = null } = {}) {
  const mod = getModule(module);
  if (!mod) throw new Error(`unknown module: ${module}`);
  const duration = Number(durationSec);
  if (!Number.isFinite(duration) || duration <= 0 || duration > RENDER_MAX_DURATION_SEC) {
    throw new Error(`durationSec must be > 0 and <= ${RENDER_MAX_DURATION_SEC}`);
  }

  const id = "spc_" + crypto.randomBytes(8).toString("hex");
  const traitMap = seedTraitMap(module);

  const specimen = {
    id,
    title: title || `${module} specimen`,
    creator: creator || "anonymous",
    ownerEmail,
    sourceModule: module,
    traitMap,
    durationSec: duration,
    audioUrl: null,
    simulated: true,
    renderState: "unavailable",
    renderId: id,
    forSale: false,
    priceCents: 0,
    createdAt: new Date().toISOString()
  };
  specimens().insert(specimen);

  // Dispatch is not completion: the specimen stays simulated until a verified
  // completion receipt arrives. If the dispatch itself fails, the specimen
  // stays unavailable — it never claims a render that was not sent.
  if (isOnline()) {
    const outputPath = renderOutputPath(id);
    let dispatched = false;
    try { fs.mkdirSync(path.dirname(outputPath), { recursive: true }); } catch { /* fall through */ }
    try { dispatched = send("/brahma/foundry/render", [id, module, duration, outputPath]); } catch { dispatched = false; }
    if (dispatched) {
      specimen.renderState = "pending";
      const timer = setTimeout(() => failPendingRender(id, "render timeout"), RENDER_TIMEOUT_MS);
      if (typeof timer.unref === "function") timer.unref();
      pendingRenders.set(id, { specimenId: id, timer });
      logEvent("specimen.render_dispatched", `${id}:${module}`);
    }
  }
  logEvent("specimen.simulated", `${id}:${module}`);
  return specimen;
}

function isOnline() {
  if (lastTelemetryAt === null) return false;
  const age = Date.now() - lastTelemetryAt;
  return age >= 0 && age <= TELEMETRY_TTL_MS;
}

module.exports = { start, send, organismState, renderSpecimen, isOnline };
