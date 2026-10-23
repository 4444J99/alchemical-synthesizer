"use strict";
/**
 * providers.js — composition providers behind one interface.
 *
 * Every provider answers the same two questions:
 *   available()  can this host actually run it, right now, with evidence?
 *   propose()    turn a prompt into note events, or fail with a typed reason
 *
 * The point of the availability probe is that "not installed" must never look like
 * "produced nothing". Tidal and Sonic Pi are not on this host; the Claude adapter
 * needs an API key this host does not have. Those report unavailable with a reason
 * instead of returning an empty pattern. The `mock` provider is always available and
 * always labelled as such — it exists so the loop can be exercised offline, not so
 * that a demo can pretend a model was called.
 */

const crypto = require("node:crypto");

const PROVIDER_NAMES = ["mock", "claude", "tidal", "sonicpi"];

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
    const time = Number(e && e.time);
    const note = Number(e && e.note);
    const vel = e && e.vel === undefined ? 0.8 : Number(e.vel);
    const dur = e && e.dur === undefined ? 0.5 : Number(e.dur);

    if (!Number.isFinite(time) || time < 0 || time > 3600) return null;
    if (!Number.isFinite(note) || note < 0 || note > 127) return null;
    if (!Number.isFinite(vel) || vel < 0 || vel > 1) return null;
    if (!Number.isFinite(dur) || dur <= 0 || dur > 30) return null;

    out.push({ time, note, vel, dur });
  }
  return out.sort((a, b) => a.time - b.time);
}

function createProviderRegistry({ env = process.env, transport, now = () => Date.now() } = {}) {
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

  const claudeModel = env.BRAHMA_CLAUDE_MODEL || null;
  const hasKey = Boolean(env.ANTHROPIC_API_KEY);

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
      available: () => hasKey,
      reason: () => (hasKey ? "api_key_present" : "not_configured: no ANTHROPIC_API_KEY"),
      note: hasKey && !claudeModel ? "set BRAHMA_CLAUDE_MODEL to pin the model" : "",
      propose: async ({ prompt }) => {
        if (!hasKey) throw new Error("claude provider unavailable: no ANTHROPIC_API_KEY");
        if (!claudeModel) throw new Error("claude provider misconfigured: set BRAHMA_CLAUDE_MODEL");

        const instruction = [
          "Compose a short monophonic pattern for a synthesizer.",
          "Respond with JSON only, no prose and no code fences:",
          '{"summary": "one line", "events": [{"time": 0.0, "note": 60, "vel": 0.8, "dur": 0.5}]}',
          "note is MIDI 0-127, vel 0-1, times and durations in seconds, at most 64 events.",
          "",
          `Prompt: ${prompt}`
        ].join("\n");

        const raw = await claudeTransport({ prompt: instruction, apiKey: env.ANTHROPIC_API_KEY, model: claudeModel }); // allow-secret
        let parsed;
        try {
          parsed = JSON.parse(stripFences(raw));
        } catch (_) {
          throw new Error("claude provider returned unparseable JSON");
        }
        const events = validateEvents(parsed.events);
        if (!events) throw new Error("claude provider returned no valid events");
        return { summary: String(parsed.summary || "model proposal").slice(0, 500), events };
      }
    },

    tidal: {
      name: "tidal",
      kind: "live",
      available: () => false,
      reason: () => "not_installed: no GHC/Tidal on this host",
      note: "live pattern engine; adapter is declared, not simulated",
      propose: async () => {
        throw new Error("tidal provider unavailable: not installed on this host");
      }
    },

    sonicpi: {
      name: "sonicpi",
      kind: "live",
      available: () => false,
      reason: () => "not_installed: no Sonic Pi on this host",
      note: "live pattern engine; adapter is declared, not simulated",
      propose: async () => {
        throw new Error("sonicpi provider unavailable: not installed on this host");
      }
    }
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
      return { name: p.name, kind: p.kind, available, reason, note: p.note, checkedAt: new Date(now()).toISOString() };
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

  return { list, get, propose, names: () => [...PROVIDER_NAMES] };
}

module.exports = { createProviderRegistry, mockProposal, validateEvents, PROVIDER_NAMES };
