"use strict";
/**
 * session.js — typed WebSocket protocol between the workbench and the gateway.
 *
 * The browser does not speak raw OSC by default. It sends typed frames; this module
 * validates them, applies the rate limit, and translates each one to the engine's
 * *real* OSC surface — no invented addresses:
 *
 *   run       register a live pattern (id, engine, instance)      -> ack
 *   event     one scheduled pattern event                         -> /brahma/live/play
 *   stop      release one pattern's instance voices               -> /brahma/engine/freeAll
 *   stop_all  engine panic (never s.freeAll: IMMUNE stays alive)  -> /brahma/live/panic
 *   status    engine health + live pattern registry               -> status
 *
 * Legacy raw OSC frames ({address, args}) are still accepted for the pre-existing
 * Cortex clients, inside the browser allowlist only.
 *
 * Errors are always typed:
 *   { type: "error", code, message, detail? }
 */

const MAX_PATTERNS = 64;
const MAX_DUR_SECS = 30; // mirrors ~live_gateway[\maxVoiceSecs]
const ID_RE = /^[A-Za-z0-9._-]{1,64}$/;

const DEFAULT_ENGINE = "prima_materia";
const DEFAULT_INSTANCE = "brahma";

/** Shared across connections: the engine is one, so its state is one. */
function createLiveSessions({ staleAfterMs = 5000, now = () => Date.now() } = {}) {
  const patterns = new Map();
  let lastPong = null;

  function recordPong(modules, voices) {
    lastPong = { modules: Number(modules) || 0, voices: Number(voices) || 0, at: now() };
  }

  function engineHealth() {
    if (!lastPong) {
      return { ok: false, reason: "no_pong_yet", modules: 0, voices: 0, lastPongAt: null, ageMs: null };
    }
    const ageMs = now() - lastPong.at;
    return {
      ok: ageMs <= staleAfterMs,
      reason: ageMs <= staleAfterMs ? "ok" : "stale",
      modules: lastPong.modules,
      voices: lastPong.voices,
      lastPongAt: new Date(lastPong.at).toISOString(),
      ageMs
    };
  }

  function addPattern(id, { engine, instance, source }) {
    if (patterns.size >= MAX_PATTERNS) return { ok: false, code: "too_many_patterns" };
    if (patterns.has(id)) return { ok: false, code: "duplicate_id" };
    const pattern = {
      id,
      engine,
      instance,
      source: typeof source === "string" ? source.slice(0, 20000) : "",
      events: 0,
      startedAt: now()
    };
    patterns.set(id, pattern);
    return { ok: true, pattern };
  }

  function bumpEvent(id) {
    const p = patterns.get(id || "");
    if (p) p.events += 1;
  }

  function removePattern(id) {
    const p = patterns.get(id);
    if (!p) return null;
    patterns.delete(id);
    return p;
  }

  function clear() {
    const ids = Array.from(patterns.keys());
    patterns.clear();
    return ids;
  }

  function list() {
    return Array.from(patterns.values()).map((p) => ({
      id: p.id,
      engine: p.engine,
      instance: p.instance,
      events: p.events,
      runningForMs: now() - p.startedAt
    }));
  }

  return { patterns, recordPong, engineHealth, addPattern, bumpEvent, removePattern, clear, list };
}

function isStr(v, max = 128) {
  return typeof v === "string" && v.length > 0 && v.length <= max;
}

function num(v, { min = -Infinity, max = Infinity, fallback = null } = {}) {
  if (typeof v !== "number" || !Number.isFinite(v)) return fallback;
  if (v < min) return min;
  if (v > max) return max;
  return v;
}

function oscArgs(args) {
  return (Array.isArray(args) ? args : []).map((arg) => {
    if (typeof arg === "number") {
      return Number.isInteger(arg) ? { type: "i", value: arg } : { type: "f", value: arg };
    }
    return { type: "s", value: String(arg) };
  });
}

/**
 * One connection's protocol handler.
 *
 * @param {object} opts
 * @param {() => string|null} opts.getRole        current role for this socket
 * @param {(role: string) => void} opts.setRole   called after a successful auth
 * @param {(value: string) => "human"|null} opts.exchangeHuman
 * @param {(value: string) => boolean} opts.isAgentToken
 * @param {(address: string, args: any[]) => void} opts.sendOsc
 * @param {string[]} opts.allowedPrefixes
 * @param {{take: (n?: number) => {ok: boolean, retryAfterMs?: number}}} opts.limiter
 * @param {ReturnType<typeof createLiveSessions>} opts.sessions
 * @param {(payload: object) => void} opts.send
 */
function createSession({
  getRole,
  setRole,
  exchangeHuman,
  isAgentToken,
  sendOsc,
  allowedPrefixes = [],
  limiter,
  sessions,
  send
}) {
  const respond = (payload) => send(payload);

  function fail(code, message, detail) {
    const frame = { type: "error", code, message };
    if (detail !== undefined) frame.detail = detail;
    respond(frame);
  }

  function requireHuman(action) {
    if (getRole() === "human") return true;
    fail("forbidden", `Human authorization required for ${action}`);
    return false;
  }

  function handleAuth(msg) {
    const token = msg.token !== undefined ? msg.token : Array.isArray(msg.args) ? msg.args[0] : undefined; // allow-secret
    if (typeof token !== "string" || !token) return fail("invalid_token", "Missing token"); // allow-secret
    if (exchangeHuman(token)) {
      setRole("human");
      return respond({ type: "auth", ok: true, role: "human" });
    }
    if (isAgentToken(token)) {
      setRole("agent");
      return respond({ type: "auth", ok: true, role: "agent" });
    }
    return fail("invalid_token", "Token rejected");
  }

  function handleRun(msg) {
    if (!requireHuman("run")) return;
    const id = isStr(msg.id, 64) ? msg.id : null;
    if (!id || !ID_RE.test(id)) return fail("bad_id", "run requires a pattern id matching [A-Za-z0-9._-]{1,64}");
    const engine = isStr(msg.engine, 64) ? msg.engine : DEFAULT_ENGINE;
    const instance = isStr(msg.instance, 64) ? msg.instance : DEFAULT_INSTANCE;

    const added = sessions.addPattern(id, { engine, instance, source: msg.source });
    if (!added.ok) return fail(added.code, `Cannot start pattern ${id}`, { size: sessions.patterns.size });

    // Ask the engine for health so the client gets a truthful status immediately.
    sendOsc("/brahma/live/ping", []);
    return respond({
      type: "ack",
      action: "run",
      id,
      engine,
      instance,
      startedAt: new Date(added.pattern.startedAt).toISOString()
    });
  }

  function handleEvent(msg) {
    if (!requireHuman("event")) return;
    const limit = limiter.take(1);
    if (!limit.ok) {
      return fail("rate_limited", "Too many events; slow the pattern down", {
        retryAfterMs: limit.retryAfterMs
      });
    }

    const note = num(msg.note, { min: 0, max: 127 });
    const vel = num(msg.vel, { min: 0, max: 1 });
    const dur = num(msg.dur, { min: 0.01, max: MAX_DUR_SECS });
    if (note === null || vel === null || dur === null) {
      return fail("bad_args", "event requires numeric note (0-127), vel (0-1), dur (>0)");
    }

    const engine = isStr(msg.engine, 64) ? msg.engine : DEFAULT_ENGINE;
    const instance = isStr(msg.instance, 64) ? msg.instance : DEFAULT_INSTANCE;
    const params = Array.isArray(msg.params) ? msg.params.slice(0, 64) : [];

    sendOsc("/brahma/live/play", [engine, instance, Math.round(note), vel, dur, ...params]);
    sessions.bumpEvent(msg.id);
  }

  function handleStop(msg) {
    if (!requireHuman("stop")) return;
    const id = isStr(msg.id, 64) ? msg.id : null;
    if (!id) return fail("bad_id", "stop requires a pattern id");

    const pattern = sessions.removePattern(id);
    if (!pattern) return fail("unknown_pattern", `No running pattern ${id}`);

    // Real engine capability: release this instance's voices, leave everything else.
    sendOsc("/brahma/engine/freeAll", [pattern.instance]);
    return respond({ type: "ack", action: "stop", id, instance: pattern.instance });
  }

  function handleStopAll() {
    if (!requireHuman("stop_all")) return;
    const ids = sessions.clear();
    sendOsc("/brahma/live/panic", []);
    return respond({ type: "ack", action: "stop_all", patterns: ids, at: new Date().toISOString() });
  }

  function handleStatus() {
    const role = getRole();
    if (role !== "human" && role !== "agent") return fail("forbidden", "Authentication required for status");
    return respond({
      type: "status",
      role,
      engine: sessions.engineHealth(),
      live: { count: sessions.patterns.size, patterns: sessions.list() },
      at: new Date().toISOString()
    });
  }

  function handleLegacyOsc(msg) {
    const address = msg.address;
    if (typeof address !== "string") return fail("bad_frame", "Message has no address");

    // Role first: an unauthenticated client learns nothing about the allowlist.
    if (!requireHuman("live engine control")) return;

    if (!allowedPrefixes.some((ns) => address.startsWith(ns))) {
      return fail("forbidden_address", `Address ${address} is not in the browser allowlist`);
    }

    const limit = limiter.take(1);
    if (!limit.ok) {
      return fail("rate_limited", "Too many messages; slow down", { retryAfterMs: limit.retryAfterMs });
    }

    sendOsc(address, oscArgs(msg.args).map((a) => a.value));
  }

  function handle(raw) {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch (_) {
      return fail("bad_json", "Frame is not valid JSON");
    }
    if (!msg || typeof msg !== "object" || Array.isArray(msg)) {
      return fail("bad_frame", "Frame must be a JSON object");
    }

    if (msg.type === "auth" || msg.address === "/brahma/auth") return handleAuth(msg);

    switch (msg.type) {
      case "run": return handleRun(msg);
      case "event": return handleEvent(msg);
      case "stop": return handleStop(msg);
      case "stop_all": return handleStopAll();
      case "status": return handleStatus();
      case undefined: return handleLegacyOsc(msg);
      default: return fail("unknown_type", `Unknown frame type ${msg.type}`);
    }
  }

  return { handle, sessions };
}

module.exports = {
  createLiveSessions,
  createSession,
  oscArgs,
  MAX_PATTERNS,
  MAX_DUR_SECS,
  DEFAULT_ENGINE,
  DEFAULT_INSTANCE
};
