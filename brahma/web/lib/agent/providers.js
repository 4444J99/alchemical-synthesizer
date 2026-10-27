"use strict";
/**
 * providers.js — composition providers behind one interface.
 *
 * Listing reads cached configuration and discovery evidence. Optional runtime
 * discovery is explicit, asynchronous and bounded; it never starts at construction.
 * Discovery does not make an unimplemented composition adapter available.
 * The mock provider remains a labelled, deterministic offline baseline.
 */

const crypto = require("node:crypto");

const PROVIDER_NAMES = Object.freeze(["mock", "claude", "gemini", "tidal", "sonicpi"]);

function hashSeed(text) {
  return crypto.createHash("sha256").update(String(text)).digest().readUInt32BE(0);
}

/** A deterministic, clearly-labelled motif. Not a model call. */
function mockProposal(prompt) {
  const seed = hashSeed(prompt || "untitled");
  const scale = [0, 2, 4, 7, 9];           // major pentatonic
  const events = [];
  for (let i = 0; i < 8; i += 1) {
    const octave = ((seed >> (i % 16)) & 1) ? 12 : 0;
    events.push({
      time: Number((i * 0.25).toFixed(3)),
      note: 48 + scale[i % scale.length] + octave,
      vel: i % 4 === 0 ? 0.9 : 0.7,
      dur: 0.22
    });
  }
  return {
    summary: `mock pentatonic motif (${events.length} events) derived from the prompt hash — no model was called`,
    events
  };
}

function stripFences(text) {
  const trimmed = String(text).trim();
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(trimmed);
  return fenced ? fenced[1] : trimmed;
}

function validateEvents(events) {
  if (!Array.isArray(events) || events.length === 0) return null;
  if (events.length > 512) return null;

  const out = [];
  for (const e of events) {
    if (!e || typeof e !== "object" || Array.isArray(e)) return null;
    const time = Number(e.time);
    const note = Number(e.note);
    const vel = e.vel === undefined ? 0.8 : Number(e.vel);
    const dur = e.dur === undefined ? 0.5 : Number(e.dur);

    if (!Number.isFinite(time) || time < 0 || time > 3600) return null;
    if (!Number.isFinite(note) || note < 0 || note > 127) return null;
    if (!Number.isFinite(vel) || vel < 0 || vel > 1) return null;
    if (!Number.isFinite(dur) || dur <= 0 || dur > 30) return null;

    out.push({ time, note, vel, dur });
  }
  return out.sort((a, b) => a.time - b.time);
}

function createProviderRegistry({ env = process.env, transport, now = () => Date.now(), probeTimeoutMs = 5000 } = {}) {
  const timeoutMs = Number.isFinite(probeTimeoutMs) && probeTimeoutMs > 0
    ? Math.min(probeTimeoutMs, 30000) : 5000;
  const probeEnv = { ...env };
  const discovery = Object.fromEntries(["tidal", "sonicpi"].map((name) => [name, {
    status: "not_probed", reason: "not_probed", checkedAt: null
  }]));
  const pending = new Map();
  let pendingAll = null;
  let closed = false;
  const probeController = new AbortController();

  async function discoverTidal() {
    // Lazy import avoids a cycle: tools also uses validateEvents. The shared
    // executor bounds output and kills the command's process group on timeout.
    const { defaultExecFile } = require("./tools");
    const { stdout } = await defaultExecFile("ghci", [
      "-ignore-dot-ghci", "-v0", "-e", "import Sound.Tidal.Context", "-e", 'putStrLn "TIDAL_OK"'
    ], { env: probeEnv, timeout: timeoutMs, maxBuffer: 64 * 1024, signal: probeController.signal });
    return /(?:^|\n)TIDAL_OK(?:\r?\n|$)/.test(stdout)
      ? { status: "detected", reason: "ghci loaded Sound.Tidal.Context" }
      : { status: "probe_failed", reason: "ghci did not confirm Sound.Tidal.Context" };
  }

  async function discoverSonicPi() {
    // Finding an application is installation evidence, not a running daemon or
    // an event-producing adapter. No OSC or playback occurs during discovery.
    let timer;
    let onAbort;
    try {
      await Promise.race([
        require("node:fs").promises.access("/Applications/Sonic Pi.app"),
        new Promise((_, reject) => {
          timer = setTimeout(() => reject(Object.assign(new Error("Sonic Pi discovery timed out"), {
            code: "ETIMEDOUT"
          })), timeoutMs);
          onAbort = () => reject(probeController.signal.reason);
          probeController.signal.addEventListener("abort", onAbort, { once: true });
        })
      ]);
      return { status: "detected", reason: "Sonic Pi.app found" };
    } finally {
      clearTimeout(timer);
      if (onAbort) probeController.signal.removeEventListener("abort", onAbort);
    }
  }

  function probeRuntime(name) {
    if (closed) return Promise.resolve(false);
    if (pending.has(name)) return pending.get(name);
    discovery[name] = { status: "probing", reason: "discovery_running", checkedAt: null };
    const task = (async () => {
      let result;
      try {
        result = await (name === "tidal" ? discoverTidal() : discoverSonicPi());
      } catch (err) {
        if (err.code === "ENOENT") {
          result = { status: "not_installed", reason: name === "tidal" ? "ghci not found" : "Sonic Pi.app not found" };
        } else if (err.code === "ETIMEDOUT") {
          result = { status: "timeout", reason: `discovery exceeded ${timeoutMs}ms` };
        } else {
          result = { status: "probe_failed", reason: String(err.message || err).slice(0, 200) };
        }
      }
      if (closed) result = { status: "closed", reason: "registry_closed" };
      discovery[name] = { ...result, checkedAt: new Date(now()).toISOString() };
      return result.status === "detected";
    })().finally(() => pending.delete(name));
    pending.set(name, task);
    return task;
  }

  function unavailableLiveProvider(name, note) {
    const reason = "adapter_not_implemented: no proposal-to-events adapter";
    return {
      name, kind: "live", available: () => false, reason: () => reason, note,
      probe: () => probeRuntime(name),
      propose: async () => { throw Object.assign(new Error(`${name}: ${reason}`), { code: "adapter_not_implemented" }); }
    };
  }

  // Injected in tests. The default performs a real API call, which is why the
  // provider reports unavailable on a host with no key rather than faking one.
  const claudeTransport = transport || (async ({ prompt, apiKey, model }) => {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01"
      },
      body: JSON.stringify({
        model,
        max_tokens: 1200,
        messages: [{ role: "user", content: prompt }]
      })
    });
    if (!res.ok) {
      throw new Error(`anthropic api ${res.status}: ${(await res.text()).slice(0, 300)}`);
    }
    const body = await res.json();
    return (body.content || []).map((c) => c.text || "").join("");
  });

  const geminiTransport = transport || (async ({ prompt, apiKey, model }) => {
    const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": apiKey
      },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { maxOutputTokens: 1200, temperature: 0.7 }
      })
    });
    if (!res.ok) {
      throw new Error(`gemini api ${res.status}: ${(await res.text()).slice(0, 300)}`);
    }
    const body = await res.json();
    const candidate = (body.candidates || [])[0];
    const parts = (candidate && candidate.content && candidate.content.parts) || [];
    return parts.map((p) => p.text || "").join("");
  });

  const configuredString = (value) => typeof value === "string" ? value.trim() : "";
  const claudeModel = configuredString(env.BRAHMA_CLAUDE_MODEL);
  const claudeApiKey = configuredString(env.ANTHROPIC_API_KEY);
  const geminiApiKey = configuredString(env.GEMINI_API_KEY) || configuredString(env.GOOGLE_API_KEY);
  const geminiModel = configuredString(env.BRAHMA_GEMINI_MODEL);

  const providers = {
    mock: {
      name: "mock",
      kind: "local",
      available: () => true,
      reason: () => "always_available",
      note: "deterministic motif; no model is called",
      propose: async ({ prompt }) => ({ summary: mockProposal(prompt).summary, events: mockProposal(prompt).events })
    },

    claude: {
      name: "claude",
      kind: "model",
      available: () => Boolean(claudeApiKey && claudeModel),
      reason: () => !claudeApiKey ? "not_configured: no ANTHROPIC_API_KEY"
        : !claudeModel ? "not_configured: set BRAHMA_CLAUDE_MODEL" : "configured",
      note: "availability requires a key and an explicit model; connectivity has not been checked",
      propose: async ({ prompt }) => {
        if (!claudeApiKey) throw new Error("claude provider unavailable: no ANTHROPIC_API_KEY");
        if (!claudeModel) throw new Error("claude provider misconfigured: set BRAHMA_CLAUDE_MODEL");

        const instruction = [
          "Compose a short monophonic pattern for a synthesizer.",
          "Respond with JSON only, no prose and no code fences:",
          '{"summary": "one line", "events": [{"time": 0.0, "note": 60, "vel": 0.8, "dur": 0.5}]}',
          "note is MIDI 0-127, vel 0-1, times and durations in seconds, at most 64 events.",
          "",
          `Prompt: ${prompt}`
        ].join("\n");

        const raw = await claudeTransport({ prompt: instruction, apiKey: claudeApiKey, model: claudeModel }); // allow-secret
        let parsed;
        try {
          parsed = JSON.parse(stripFences(raw));
        } catch (_) {
          throw new Error("claude provider returned unparseable JSON");
        }
        const events = validateEvents(parsed && parsed.events);
        if (!events) throw new Error("claude provider returned no valid events");
        return { summary: String(parsed.summary || "model proposal").slice(0, 500), events };
      }
    },

    gemini: {
      name: "gemini",
      kind: "model",
      available: () => Boolean(geminiApiKey && geminiModel),
      reason: () => !geminiApiKey ? "not_configured: no GEMINI_API_KEY or GOOGLE_API_KEY"
        : !geminiModel ? "not_configured: set BRAHMA_GEMINI_MODEL" : "configured",
      note: "availability requires a key and an explicit model; connectivity has not been checked",
      propose: async ({ prompt }) => {
        if (!geminiApiKey) throw new Error("gemini provider unavailable: no GEMINI_API_KEY or GOOGLE_API_KEY");
        if (!geminiModel) throw new Error("gemini provider misconfigured: set BRAHMA_GEMINI_MODEL");

        const instruction = [
          "Compose a short monophonic pattern for a synthesizer.",
          "Respond with JSON only, no prose and no code fences:",
          '{"summary": "one line", "events": [{"time": 0.0, "note": 60, "vel": 0.8, "dur": 0.5}]}',
          "note is MIDI 0-127, vel 0-1, times and durations in seconds, at most 64 events.",
          "",
          `Prompt: ${prompt}`
        ].join("\n");

        const raw = await geminiTransport({ prompt: instruction, apiKey: geminiApiKey, model: geminiModel }); // allow-secret
        let parsed;
        try {
          parsed = JSON.parse(stripFences(raw));
        } catch (_) {
          throw new Error("gemini provider returned unparseable JSON");
        }
        const events = validateEvents(parsed && parsed.events);
        if (!events) throw new Error("gemini provider returned no valid events");
        return { summary: String(parsed.summary || "model proposal").slice(0, 500), events };
      }
    },

    tidal: unavailableLiveProvider("tidal", "GHCi/Tidal discovery is optional; composition adapter is not implemented"),
    sonicpi: unavailableLiveProvider("sonicpi", "Sonic Pi discovery is optional; composition adapter is not implemented")
  };

  function list() {
    return PROVIDER_NAMES.map((name) => {
      const p = providers[name];
      let available = false;
      let reason = "unknown";
      try {
        available = Boolean(p.available());
        reason = p.reason();
      } catch (err) {
        reason = `probe_failed: ${err.message}`;
      }
      return {
        name: p.name, kind: p.kind, available, reason, note: p.note,
        checkedAt: new Date(now()).toISOString(),
        ...(discovery[name] ? { discovery: { ...discovery[name] } } : {})
      };
    });
  }

  function get(name) {
    return providers[String(name)] || null;
  }

  async function propose(name, { prompt } = {}) {
    const provider = get(name);
    if (!provider) {
      return { ok: false, code: "unknown_provider", message: `Unknown provider ${name}` };
    }
    if (!provider.available()) {
      // Unavailable is a hard, typed answer — never an empty pattern.
      return { ok: false, code: "provider_unavailable", message: `${name}: ${provider.reason()}` };
    }

    try {
      const proposal = await provider.propose({ prompt: String(prompt || "") });
      const events = validateEvents(proposal.events);
      if (!events) return { ok: false, code: "provider_bad_proposal", message: `${name} returned no valid events` };
      return { ok: true, provider: name, summary: proposal.summary, events };
    } catch (err) {
      return { ok: false, code: "provider_error", message: err.message };
    }
  }

  function probeAll() {
    if (closed) return Promise.resolve({ tidal: false, sonicpi: false });
    if (pendingAll) return pendingAll;
    pendingAll = Promise.all([probeRuntime("tidal"), probeRuntime("sonicpi")])
      .then(([tidal, sonicpi]) => ({ tidal, sonicpi }))
      .finally(() => { pendingAll = null; });
    return pendingAll;
  }

  function close() {
    if (closed) return;
    closed = true;
    probeController.abort(new Error("provider registry closed"));
    for (const name of Object.keys(discovery)) {
      discovery[name] = { status: "closed", reason: "registry_closed", checkedAt: new Date(now()).toISOString() };
    }
  }

  return { list, get, propose, names: () => [...PROVIDER_NAMES], probe: probeAll, close };
}

module.exports = { createProviderRegistry, mockProposal, validateEvents, PROVIDER_NAMES };
