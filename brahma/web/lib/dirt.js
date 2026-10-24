"use strict";
/**
 * dirt.js — Dirt Protocol Bridge for TidalCycles and Seatbelt Sandbox.
 *
 * Ingress: UDP 127.0.0.1:57130 (configurable via options.port or BRAHMA_DIRT_PORT)
 * Egress:  UDP 127.0.0.1:57120 (configurable via options.scPort or BRAHMA_SC_PORT)
 *
 * Protocol:
 *   Accepts /dirt/play and /play2 OSC messages from TidalCycles/Strudel.
 *   Extracts: sound/engine ('s'), note ('n'), gain, delta/duration, and parameters.
 *   Translates to /brahma/live/play and forwards to SuperCollider.
 *   Also routes /dirt/panic to /brahma/live/panic.
 */

const osc = require("osc");
const EventEmitter = require("events");

const DEFAULT_DIRT_PORT = 57130;
const DEFAULT_SC_PORT = 57120;
const DEFAULT_ENGINE = "prima_materia";
const MAX_VOICE_SECS = 30;

// Internal Tidal / Dirt protocol keys to filter from extra synth parameters
const RESERVED_KEYS = new Set([
  "s", "sound",
  "n", "note", "midinote",
  "gain", "velocity", "vel",
  "delta", "dur", "sustain",
  "instance", "orbit",
  "cps", "cycle"
]);

/**
 * Normalizes incoming arguments from flat array, osc metadata array, or dictionary object.
 * @param {Array|object} args
 * @returns {Record<string, any>}
 */
function parseDirtArgs(args) {
  if (!args) return {};
  if (!Array.isArray(args)) {
    if (typeof args === "object" && args !== null) return { ...args };
    return {};
  }

  const out = {};
  // Handle array of {type, value} metadata objects from osc library
  if (args.length > 0 && typeof args[0] === "object" && args[0] !== null && "value" in args[0]) {
    for (let i = 0; i < args.length - 1; i += 2) {
      const k = String(args[i].value);
      const v = args[i + 1].value;
      out[k] = v;
    }
    return out;
  }

  // Handle flat alternating key-value array
  for (let i = 0; i < args.length - 1; i += 2) {
    const k = String(args[i]);
    const v = args[i + 1];
    out[k] = v;
  }
  return out;
}

/**
 * Translates a Dirt OSC message (/dirt/play or /play2) into /brahma/live/play format.
 * @param {object} oscMsg
 * @param {string} oscMsg.address
 * @param {Array|object} oscMsg.args
 * @param {object} [options]
 * @param {boolean} [options.metadata=true]
 * @returns {object|null} translated message or null if address is unsupported
 */
function translateDirtMessage(oscMsg, { metadata = true } = {}) {
  if (!oscMsg || typeof oscMsg.address !== "string") return null;

  const addr = oscMsg.address;

  // Handle panic command forwarding
  if (addr === "/dirt/panic" || addr === "/brahma/live/panic") {
    return {
      address: "/brahma/live/panic",
      args: []
    };
  }

  if (addr !== "/dirt/play" && addr !== "/play2") {
    return null;
  }

  const params = parseDirtArgs(oscMsg.args);

  // 1. Engine ('s' or 'sound')
  const rawEngine = params.s !== undefined ? params.s : params.sound;
  const engine = (rawEngine ? String(rawEngine) : DEFAULT_ENGINE).trim() || DEFAULT_ENGINE;

  // 2. Instance identifier
  const orbit = params.orbit !== undefined ? params.orbit : 0;
  const instance = params.instance ? String(params.instance) : `dirt_${engine}_${orbit}`;

  // 3. Note ('n', 'note', or 'midinote')
  let noteNum = 60;
  if (typeof params.midinote === "number") noteNum = params.midinote;
  else if (typeof params.n === "number") noteNum = params.n;
  else if (typeof params.note === "number") noteNum = params.note;
  else if (params.n !== undefined && !isNaN(Number(params.n))) noteNum = Number(params.n);
  else if (params.note !== undefined && !isNaN(Number(params.note))) noteNum = Number(params.note);
  const note = Math.max(0, Math.min(127, Math.round(noteNum)));

  // 4. Velocity ('gain', 'velocity', 'vel')
  let rawGain = 0.8;
  if (typeof params.gain === "number") rawGain = params.gain;
  else if (typeof params.velocity === "number") rawGain = params.velocity;
  else if (typeof params.vel === "number") rawGain = params.vel;
  else if (params.gain !== undefined && !isNaN(Number(params.gain))) rawGain = Number(params.gain);
  else if (params.velocity !== undefined && !isNaN(Number(params.velocity))) rawGain = Number(params.velocity);
  const vel = Math.max(0.0, Math.min(1.0, rawGain));

  // 5. Duration ('delta', 'dur', 'sustain')
  let rawDur = 0.5;
  if (typeof params.delta === "number") rawDur = params.delta;
  else if (typeof params.dur === "number") rawDur = params.dur;
  else if (typeof params.sustain === "number") rawDur = params.sustain;
  else if (params.delta !== undefined && !isNaN(Number(params.delta))) rawDur = Number(params.delta);
  else if (params.dur !== undefined && !isNaN(Number(params.dur))) rawDur = Number(params.dur);
  const dur = Math.max(0.01, Math.min(MAX_VOICE_SECS, rawDur));

  // 6. Extra synthesis parameters
  const extraArgs = [];
  for (const [k, v] of Object.entries(params)) {
    if (!RESERVED_KEYS.has(k)) {
      const numVal = Number(v);
      if (Number.isFinite(numVal)) {
        if (metadata) {
          extraArgs.push({ type: "s", value: k });
          extraArgs.push(Number.isInteger(numVal) ? { type: "i", value: numVal } : { type: "f", value: numVal });
        } else {
          extraArgs.push(k, numVal);
        }
      }
    }
  }

  if (metadata) {
    return {
      address: "/brahma/live/play",
      args: [
        { type: "s", value: engine },
        { type: "s", value: instance },
        { type: "i", value: note },
        { type: "f", value: vel },
        { type: "f", value: dur },
        ...extraArgs
      ]
    };
  } else {
    return {
      address: "/brahma/live/play",
      args: [engine, instance, note, vel, dur, ...extraArgs]
    };
  }
}

/**
 * Creates and initializes the Dirt protocol bridge UDP listener and sender.
 * @param {object} [options]
 * @param {number} [options.port=57130] Ingress UDP port
 * @param {number} [options.scPort=57120] SuperCollider UDP port
 * @param {string} [options.scHost="127.0.0.1"] SuperCollider target host
 * @param {string} [options.bindAddress="127.0.0.1"] Local bind interface
 * @param {boolean} [options.metadata=true] Metadata format for OSC sender
 * @returns {EventEmitter & { start: Function, close: Function, status: Function, udpListener: object, scSender: object }}
 */
function createDirtBridge({
  port = DEFAULT_DIRT_PORT,
  scPort = DEFAULT_SC_PORT,
  scHost = "127.0.0.1",
  bindAddress = "127.0.0.1",
  metadata = true
} = {}) {
  const emitter = new EventEmitter();

  const udpListener = new osc.UDPPort({
    localAddress: bindAddress,
    localPort: port,
    metadata: true
  });

  const scSender = new osc.UDPPort({
    localAddress: bindAddress,
    localPort: 0,
    remoteAddress: scHost,
    remotePort: scPort,
    metadata: metadata
  });

  let isOpen = false;

  udpListener.on("ready", () => {
    isOpen = true;
    emitter.emit("ready", { port, scPort, scHost });
  });

  udpListener.on("message", (oscMsg, timeTag, info) => {
    try {
      const translated = translateDirtMessage(oscMsg, { metadata });
      if (translated) {
        scSender.send(translated);
        emitter.emit("forward", { original: oscMsg, translated, sender: info });
      }
    } catch (err) {
      emitter.emit("error", err);
    }
  });

  udpListener.on("error", (err) => {
    emitter.emit("error", err);
  });

  scSender.on("error", (err) => {
    emitter.emit("error", err);
  });

  function start() {
    udpListener.open();
    scSender.open();
    return emitter;
  }

  function close() {
    isOpen = false;
    try { udpListener.close(); } catch (_) {}
    try { scSender.close(); } catch (_) {}
    emitter.emit("close");
  }

  function status() {
    return {
      open: isOpen,
      dirtPort: port,
      scPort: scPort,
      scHost: scHost,
      bindAddress: bindAddress
    };
  }

  return Object.assign(emitter, { start, close, status, udpListener, scSender });
}

module.exports = {
  createDirtBridge,
  translateDirtMessage,
  parseDirtArgs,
  DEFAULT_DIRT_PORT,
  DEFAULT_SC_PORT,
  DEFAULT_ENGINE,
  MAX_VOICE_SECS,
  RESERVED_KEYS
};
