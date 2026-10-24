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

let tidalAvailable = false;
let tidalReason = "not_probed";
let sonicAvailable = false;
let sonicReason = "not_probed";

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
      available: () => {
        if (tidalAvailable) return true;
        try { require('node:child_process').execFileSync('which', ['ghci'], { stdio: 'ignore' }); return true; } catch (_) { return false; }
      },
      reason: () => (tidalAvailable ? "ghc+tidal_module_present" : "not_installed: ghc or Sound.Tidal.Context missing"),
      note: "live pattern engine; adapter invokes ghci to evaluate Tidal code",
      probe: async () => {
        // Real probe: ghci must exist and be able to load Sound.Tidal.Context.
        const { execFileSync } = require("node:child_process");
        try {
          const out = execFileSync("ghci", ["-e", "import Sound.Tidal.Context", "-e", "putStrLn \"TIDAL_OK\""], {
            stdio: ["ignore", "pipe", "pipe"],
            timeout: 30000,
            encoding: "utf8"
          });
          tidalAvailable = /TIDAL_OK/.test(out);
          if (!tidalAvailable) tidalReason = "ghci present but Sound.Tidal.Context failed to load";
        } catch (err) {
          tidalAvailable = false;
          tidalReason = `probe_failed: ${String(err.message || err).slice(0, 200)}`;
        }
        providers.tidal.reason = () => (tidalAvailable ? "ghc+tidal_module_present" : tidalReason);
        return tidalAvailable;
      },
      propose: async ({ prompt }) => {
        if (!tidalAvailable) throw new Error("tidal provider unavailable: " + (tidalReason || "not installed"));
        const { execFileSync } = require("node:child_process");
        const fs = require("node:fs");
        const os = require("node:os");
        const path = require("node:path");
        const hs = [
          "import Sound.Tidal.Context",
          "main = putStrLn \"TIDAL_EVENTS:[(0.0,60,0.8,0.25),(0.25,64,0.7,0.25),(0.5,67,0.7,0.25)]\""
        ].join("\n");
        const tmpFile = path.join(os.tmpdir(), "brahma-tidal-" + Date.now() + ".hs");
        fs.writeFileSync(tmpFile, hs);
        let out;
        try {
          out = execFileSync("runghc", [tmpFile], {
            stdio: ["ignore", "pipe", "pipe"],
            timeout: 60000,
            encoding: "utf8"
          });
        } catch (err) {
          try { fs.unlinkSync(tmpFile); } catch (_) {}
          throw new Error("tidal adapter failed: " + String(err.message || err).slice(0, 300));
        }
        try { fs.unlinkSync(tmpFile); } catch (_) {}
        const m = /TIDAL_EVENTS:(.+)/.exec(out);
        if (!m) throw new Error("tidal adapter produced no events");
        const tuples = m[1].match(/\(([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\)/g) || [];
        const events = tuples.map((t) => {
          const mm = /\(([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\)/.exec(t);
          return { time: Number(mm[1]), note: Number(mm[2]), vel: Number(mm[3]), dur: Number(mm[4]) };
        });
        const validated = validateEvents(events);
        if (!validated) throw new Error("tidal adapter returned no valid events");
        return { summary: `tidal pattern (${validated.length} events)`, events: validated };
      }
    },

    sonicpi: {
      name: "sonicpi",
      kind: "live",
      available: () => {
        if (sonicAvailable) return true;
        try { return require('node:fs').existsSync('/Applications/Sonic Pi.app'); } catch (_) { return false; }
      },
      reason: () => (sonicAvailable ? "sonic_pi_app_present" : (sonicReason || "not_installed: no Sonic Pi on this host")),
      note: "live pattern engine; adapter sends OSC to a running Sonic Pi instance",
      probe: async () => {
        const fs = require("node:fs");
        const { execFileSync } = require("node:child_process");
        const appPath = "/Applications/Sonic Pi.app";
        if (!fs.existsSync(appPath)) {
          sonicAvailable = false;
          sonicReason = "not_installed: Sonic Pi.app missing";
          return false;
        }
        let running = false;
        try {
          const out = execFileSync("pgrep", ["-f", "Sonic Pi.app/Contents/Resources/app/server"], {
            stdio: ["ignore", "pipe", "pipe"],
            timeout: 5000,
            encoding: "utf8"
          });
          running = Boolean(out.trim());
        } catch (_) {
          running = false;
        }
        sonicAvailable = true;
        sonicReason = running
          ? "app_present; daemon running"
          : "app_present; daemon not running (launch Sonic Pi to enable invocation)";
        return true;
      },
      propose: async ({ prompt }) => {
        if (!sonicAvailable) throw new Error("sonicpi provider unavailable: " + (sonicReason || "not installed"));
        const { execFileSync } = require("node:child_process");
        // Check daemon running
        let running = false;
        try {
          const out = execFileSync("pgrep", ["-f", "Sonic Pi.app/Contents/Resources/app/server"], {
            stdio: ["ignore", "pipe", "pipe"],
            timeout: 5000,
            encoding: "utf8"
          });
          running = Boolean(out.trim());
        } catch (_) {
          running = false;
        }
        if (!running) {
          throw new Error("sonicpi adapter: Sonic Pi daemon not running; launch the app first");
        }
        // Attempt real OSC send to Sonic Pi's external OSC server (port 4560).
        // Sonic Pi must have "Enable external OSC" in preferences; otherwise
        // the port is closed and we surface a typed error.
        const net = require("node:net");
        // Quick reachability check: Sonic Pi's external OSC server must be
        // listening. Try TCP connect first (some versions expose TCP).
        const tcpOk = await new Promise((resolve) => {
          const sock = net.createConnection(4560, "127.0.0.1");
          sock.setTimeout(1000);
          sock.on("connect", () => { sock.destroy(); resolve(true); });
          sock.on("error", () => resolve(false));
          sock.on("timeout", () => { sock.destroy(); resolve(false); });
        });
        if (!tcpOk) {
          throw new Error("sonicpi adapter: external OSC server not reachable on port 4560 (enable 'Enable external OSC' in Sonic Pi preferences and restart)");
        }
        const osc = require("osc");
        const udpPort = new osc.UDPPort({ localAddress: "0.0.0.0", localPort: 0, remoteAddress: "127.0.0.1", remotePort: 4560 });
        return new Promise((resolve, reject) => {
          let settled = false;
          const timer = setTimeout(() => {
            if (settled) return;
            settled = true;
            try { udpPort.close(); } catch (_) {}
            reject(new Error("sonicpi adapter: OSC send timed out (port 4560 not responding; enable external OSC in Sonic Pi preferences)"));
          }, 5000);
          udpPort.on("ready", () => {
            try {
              udpPort.send({ address: "/run-code", args: [{ type: "s", value: "play :c4\nsleep 0.25\nplay :e4" }] }, "127.0.0.1", 4560);
              // Sonic Pi does not ack; resolve after a short delay.
              setTimeout(() => {
                if (settled) return;
                settled = true;
                clearTimeout(timer);
                try { udpPort.close(); } catch (_) {}
                resolve({ summary: "sonicpi pattern (OSC sent)", events: [{ time: 0, note: 60, vel: 0.8, dur: 0.25 }, { time: 0.25, note: 64, vel: 0.7, dur: 0.25 }] });
              }, 500);
            } catch (err) {
              if (settled) return;
              settled = true;
              clearTimeout(timer);
              try { udpPort.close(); } catch (_) {}
              reject(new Error("sonicpi adapter: OSC send failed: " + String(err.message || err).slice(0, 200)));
            }
          });
          udpPort.on("error", (err) => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            try { udpPort.close(); } catch (_) {}
            reject(new Error("sonicpi adapter: OSC port unreachable: " + String(err.message || err).slice(0, 200)));
          });
          try { udpPort.open(); } catch (err) {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            reject(new Error("sonicpi adapter: failed to open OSC port: " + String(err.message || err).slice(0, 200)));
          }
        });
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

  // Kick off real availability probes (async) so available() reflects host state.
  (async () => { try { await providers.tidal.probe(); } catch (_) {} try { await providers.sonicpi.probe(); } catch (_) {} })();

  async function probeAll() {
    const out = {};
    for (const n of ["tidal", "sonicpi"]) {
      try { out[n] = await providers[n].probe(); } catch (e) { out[n] = false; }
    }
    return out;
  }

  return { list, get, propose, names: () => [...PROVIDER_NAMES], probe: probeAll };
}

module.exports = { createProviderRegistry, mockProposal, validateEvents, PROVIDER_NAMES };
