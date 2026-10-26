"use strict";
/**
 * engine.js — Bridge to the SuperCollider Brahma engine over OSC.
 *
 * The Foundry must run whether or not a live SC server is present (so it is
 * deployable to the cloud today, with the audio engine local to performers).
 * - When SC is observed, organism telemetry flows in on 57122 and commands go
 *   out on 57120, exactly matching the existing brahma/web bridge topology.
 * - render_specimen produces a *simulated* specimen record: this bridge has no
 *   implemented render-completion or artifact-ingestion contract.
 */

const crypto = require("crypto");
const { collection, logEvent } = require("./store");
const { upsertFromRegistry, getModule, seedTraitMap } = require("./catalog");

const OSC_RECV_PORT = Number(process.env.OSC_RECV_PORT || 57122);
const OSC_SEND_PORT = Number(process.env.OSC_SEND_PORT || 57120);
const SC_HOST = process.env.SC_HOST || "127.0.0.1";
const TELEMETRY_TTL_MS = 2000;

const specimens = () => collection("specimens");

// Live organism telemetry keyed by entityId.
const organisms = new Map();
let lastTelemetryAt = null;
let udpPort = null;
let sendPort = null;

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
    udpPort.on("close", () => { lastTelemetryAt = null; organisms.clear(); });
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
  return [...organisms.values()];
}

/**
 * Create a simulated specimen record. Engine telemetry does not establish that
 * audio was rendered, and no completion/artifact contract is implemented here.
 * Ownership is supplied separately by the authenticated capability caller.
 */
function renderSpecimen({ module, title, creator, durationSec = 4 }, { ownerEmail = null } = {}) {
  const mod = getModule(module);
  if (!mod) throw new Error(`unknown module: ${module}`);

  const id = "spc_" + crypto.randomBytes(8).toString("hex");
  const traitMap = seedTraitMap(module);

  const specimen = {
    id,
    title: title || `${module} specimen`,
    creator: creator || "anonymous",
    ownerEmail,
    sourceModule: module,
    traitMap,
    durationSec: Number(durationSec),
    audioUrl: null,
    simulated: true,
    forSale: false,
    priceCents: 0,
    createdAt: new Date().toISOString()
  };
  specimens().insert(specimen);
  logEvent("specimen.simulated", `${id}:${module}`);
  return specimen;
}

function isOnline() {
  if (lastTelemetryAt === null) return false;
  const age = Date.now() - lastTelemetryAt;
  return age >= 0 && age <= TELEMETRY_TTL_MS;
}

module.exports = { start, send, organismState, renderSpecimen, isOnline };
