# AETHER — Plan to the Omega (all paths)

> Brahma as a living radio: it **listens**, **transmutes**, and **broadcasts** its own
> generative, evolving stream — a self-playing, radio-eating, playable sampler-organism
> whose home page *is* the funnel and whose packaged specimens *are* the shop.

This is the strategic plan for the **AETHER** phase (see `ROADMAP.md`). It is grounded in
Brahma's own genesis design (`docs/design/*`, `docs/logos/*`, `docs/the-universal-synthesizer.md`)
and in an excavation of prior/parallel streaming work across the ecosystem, so we **converge**
onto deployed machinery rather than rebuild it. `Listen` shipped (PR #24); this plan covers
`Broadcast` and everything beyond, to the omega.

---

## 0. The reframe (from the genesis docs)

The stream is not a new feature bolted on — it is Brahma's stated telos finally made visible.
Four facts from the design corpus are load-bearing for every path below:

- **Brahma is the cosmos, not the creature.** `docs/logos/telos.md`: Brahma "generates worlds,
  laws, and beings, then allows them to conflict, evolve, fuse, and collapse within his creation
  without intervening… generative rather than absorptive." The broadcast engine is therefore an
  **organism hosted inside Brahma** (the already-designed *Host Body always-on chassis* +
  *Global Cell Cycle / METABOLISM*), never Brahma itself. This boundary must not be blurred.
- **The transceiver is the five sampler creatures eating.** *"Every patch is an act of capture;
  every performance is defined by what the system is allowed to consume."* "Eating radio" =
  **Mnemosyne / Protean Hound / Chrysalid Siren / Ossuary Monk / Janiform Child** absorbing a
  live feed at operator-controlled **Fidelity N (0–100%)**, tagged with lineage — exactly what
  `forge/tune.py`'s provenance sidecar (`<out>.source.json`) already records.
- **It already plays itself.** `docs/logos/pragma.md`: an **auto-demo at boot** (Prima Materia +
  MOIRAI + Euclidean + Lorenz), **generative drivers are first-class inputs** (Lorenz / Markov /
  cellular automata / CHRONOS), and organism state is **already broadcast at 10 Hz** to the Web
  Cortex (`/brahma/organism/update [id] [type] [coherence] [entropy]`). The self-perpetuating
  living system exists on paper and partly in code.
- **The honesty seam.** `docs/logos/pragma.md` refuses to oversell: **Coherence / Fidelity /
  Entropy are not yet real measurements.** This plan surfaces them as *provisional inner-life
  indicators* and never sells them as science. The legible proof is **before/after NRT demo
  specimens**, per `docs/surfaces/market.md`.

---

## 1. The Ω (omega)

> *"The telos is reached not when the instrument is finished, but when it can no longer be told
> apart from the things it has consumed — and when letting it consume you back becomes a form of
> mastery."* — `docs/logos/telos.md`

**AETHER's omega:** Brahma as a sovereign, always-on **living radio** — a self-playing,
radio-eating, playable **sampler-organism** whose *unrepeatable* performance streams online
(*"power-up initializes amnesia; power-down is death; recording is documentation of a specimen
that will never exist again"*), whose landing page **is** the funnel, whose packaged specimens
**are** the shop, and which grows a **lineage, not a loop** — the **Ouroboros**, *"where the
output re-enters as input,"* each absorbed identity itself a world that can be re-absorbed. Sound
is *"substrate zero"*; the same engine later absorbs non-audio. *One engine, many realities.*

---

## 2. Architecture — two planes, mapped to Brahma's organisms

### Generator plane (inside Brahma — the one genuinely new muscle)
The **Host Body always-on chassis** (from `docs/design/alchemical-synthesis-Absorption-Fusion-Synth-Design.md`,
"Layer A — the always-on chassis": stability, timing, safety limits, metabolism) hosts a
generative organism:

- **Global Cell Cycle / METABOLISM** drives macro-phases over time
  (*"bulks up every 32 bars, then sheds complexity"*) — this is the "conductor," but as a
  resident organism, not as Brahma.
- **Generative drivers** (Lorenz / Markov / cellular automata / CHRONOS) modulate parameters —
  already first-class in `docs/logos/alchemical-io.md`.
- **The five sampler creatures** are the named intake organs for freshly-`tune`d web audio.
- **Relinquished AUTO-equip** (`~egAutoLoop` in `docs/design/alchemical-synthesis-Relinquished-monster-process.md`)
  autonomously binds a donor stream when signal exceeds threshold, honoring the **Single-Equip
  Constraint** (one donor at a time; multi-stream ⇒ assign creatures or stage equip cycles).
- **FSAP** lossless accumulation (*"the instrument becomes more itself over time"*).
- **IMMUNE governor** is the last word before any output; **AdamKadmon** validates the trait map.
- **10 Hz telemetry** already streams organism state to the Web Cortex.

First realization: **segmented-NRT** — render evolving consecutive A/V segments, carrying organism
state forward, reusing `forge/bounce.sh` / `forge/stemforge.py` / `forge/render_video.mjs`
verbatim. No realtime-audio device required.

### Distribution plane (converged from the deployed estate — nothing new to invent)
`ffmpeg` segments the generator into **live HLS** → **R2** → a **web player** → the **landing
page = funnel**. Every piece already exists and is deployed elsewhere (see §3).

---

## 3. Convergence map (excavation, 2026-07-02)

Five read-only scouts swept the ecosystem. The stream is ~80% already-deployed parts + the one
new generator muscle. **Converge, don't rebuild.**

| Source | State | What it gives AETHER |
|---|---|---|
| **a-mavs-olevm** (`etceter4.com`) | DEPLOYED | The **player + transcoder**: `theatron/` HLS.js player (`js/media/video/EnhancedVideoPlayer.js` 880 LOC + `HLSLoader.js`), `js/media/MediaURLResolver.js` → **R2 CDN**, `scripts/transcode-video.js` (ffmpeg HLS, **VOD-only** → flip `-hls_playlist_type event`/rolling for live), audio-reactive p5/WebGL shader (`js/sketches/audioReactiveShader.js`, currently simulated → wire to real stream) |
| **speech-score-engine** | DEPLOYED | The **browser audio engine** (`apps/web/public/prototypes/tracker-engine.js`: `AudioBufferSourceNode` + rAF scheduling + humanization/pan/LFO; loops a *finite* score) + **CF Pages free static deploy** (`output:'export'`, git-integration) + a clip-timeline editor |
| **media-ark** | deploy-ready | **CF Containers** deploy pattern (`Dockerfile` + `wrangler containers`, authed `CF-4444j99`, R2), gated on $5/mo Workers Paid = lever `L-MEDIA-ARK-HOST` |
| **multi-camera--livestream--framework** | WORKING | RTMP **operator** kit — `broadcast.yaml` `streaming.cdn` env-sink, `health-check.sh` pre-flight guardian, launch/shutdown lifecycle, pitch-page shell. *Idioms only* (RTMP ≠ HLS) |
| **audio-synthesis-bridge** | prototype | OSC↔WebAudio **generative-bridge** pattern (the source→synthesis seam; Brahma's SC/OSC engine fills it) |
| **audio-orb** (`a-mavs-olevm/absorb-alchemize`) | WORKING | Real-time bidirectional audio + **3D THREE.js reactive visuals** (bloom/FXAA/shaders) — the realtime front-end template |
| **synth-drum-machine.tsx** (`docs/absorb-alchemize`) | WORKING | A browser **playable synth/sequencer** surface (6 synth types, LFOs, mod-matrix, MIDI) |
| **carrier-wave--zeitgeist-thesis** | thesis | Media-*theory* only — brand/naming, no machinery |
| `my-knowledge-base/config/profiles/remote-broadcast.json` | design spec | RTMP/SRT contract (bitrate ladder, audio chain) — defaults to YouTube/Twitch (rented; **diverges** from the sovereign stance) |

**Conflict flagged:** nobody has wired a *generative* source to a *live* stream — speech-score-engine
loops a finite score; etceter4's reactivity runs on simulated audio. That gap is Brahma's unique
contribution.

---

## 4. All paths — the navigable space

Five axes fork independently; any concrete configuration picks one (or a sequence) per axis.
**★ = recommended first move.**

- **A · Generation** — **A1 segmented-NRT ★** (device-free, sovereign, reuses shipped renderers;
  segment-latency) · A2 realtime scsynth + capture (true live, "mess around"; needs BlackHole/JACK) ·
  A3 hybrid (realtime engine you play, NRT tees off it).
- **B · Transport** — **B1 HLS → R2 ★** (sovereign static) · B2 Icecast/Owncast (self-host,
  audio-only true-live) · B3 RTMP → YouTube/Twitch (rented reach = **re-broadcast lure**, not home).
- **C · Surface** — **C1 theatron HLS player ★** · C2 audio-orb 3D WebGL reactive presence ·
  C3 Visual Cortex Etz Chaim (already 10 Hz telemetry-fed). All atop **landing = funnel** +
  packaged-track archive.
- **D · Host** — **D1 local proof ★** (no gate) · D2 CF Pages free static · D3 CF Containers 24/7
  ($5/mo gate `L-MEDIA-ARK-HOST`) · D4 Vercel + R2.
- **E · Identity** — **E4 all unified ★** = E1 self-playing organism (auto-demo / Cell Cycle) +
  E2 transceiver (creatures eat streams at Fidelity N) + E3 playable sampler instrument.

### The sampler instrument (E3) — from the ChatGPT tracker brainstorms
The owner's original composition thinking (raw ChatGPT exports, shared DNA with speech-score-engine)
defines how "a sampler" becomes a real instrument and how the stream *evolves structure*:

- **"Tracker-brained, Ableton-bodied."** Three-view interaction grammar: **PATTERN** (tracker
  rows/columns/per-cell commands) · **SESSION** (clip launch / recombination) · **ARRANGEMENT**
  (linear timeline / automation).
- **Per-cell command language** (RT ratchet, OV overlap, ST stutter, HU humanize, DN density, …) —
  *"where the system stops being playback and becomes compositional infrastructure."*
- **The generative arc: READABLE → CLUSTER → DISPERSAL** — the owner's original model for how a
  work evolves over time (linear → repeating redistributed clusters → atomized fragments). This is
  the seed of the Cell Cycle's macro-phase behavior.
- **3-level content bank** (line / phrase-cluster / atomized fragment) → maps directly to a Brahma
  sample bank with layered granularity.
- **Mutable `scene` vs immutable `scene_version`** — trust-critical for shareable/broadcastable
  specimens.
- **Injectable render adapter** (`PHRASE_EVENT → VOICE_RENDER_ADAPTER → audio`; the score never
  knows the backend) — the same pattern lets the tracker drive Brahma's forge/NRT or a live engine
  by config, not code.
- Grafting surface: `docs/absorb-alchemize/synth-drum-machine.tsx`.

---

## 5. The recommended traversal (smallest reversible first)

1. **Broadcast — local proof** · `A1 + B1 + C1/C3 + D1` — the Cell-Cycle generator drifts params +
   folds a `tune` capture → segmented-NRT → **live-HLS** (flip etceter4's `transcode-video.js`) →
   grafted **theatron** player, proven end-to-end locally. *(The one new muscle; everything else
   grafts. Coherence/Entropy labeled provisional.)*
2. **Home = funnel** · landing page = live player + packaged-track archive + waitlist
   (`POST /api/v1/waitlist`, real audio at `product/src/api/rest.js:65`) → deploy static (D2 / D4).
3. **24/7 sovereign** · D3 CF Container generator — gated on `L-MEDIA-ARK-HOST` ($5/mo Workers Paid).
4. **Playable / realtime** · A2/A3 + C2 audio-orb + E3 tracker instrument — "mess around live."
5. **Reach** · B3 RTMP re-broadcast lure to YouTube/Twitch (converge livestream-framework CDN sink).
6. **Ω · Ouroboros** · viewers submit a stream URL → a creature eats it live; a lineage browser;
   the "consume you back" loop; then substrate-agnostic (absorb non-audio).

---

## 6. Human-gated decision atoms (do not silently decide)

- **Rights posture** on published/sold sampled material (safe default: publish only
  rights-cleared / CC0 / public-domain / unrecognizably-transformed; recognizable rips stay
  private R&D). Partly operationalized by `stations.json` + `tune.py --publish-safe-only`.
- **Brahma's social handle / identity** (the studio face is text/voice-branded; Brahma music needs
  its own identity).
- **First public deploy** (merging a deploy-trigger path is the deploy).
- **$5/mo Workers Paid** (`L-MEDIA-ARK-HOST`) for the 24/7 container path.
- **Local virtual-audio-device install** (BlackHole/JACK) for any realtime (A2/A3) path.

## 7. Honesty ledger (invariant, from `docs/logos/pragma.md`)

- Coherence / Fidelity / Entropy ship **labeled provisional** — not sold as real measurement.
- **Demo specimens** (before/after NRT artifacts) are the legible proof of the wedge.
- Productive imperfection is by design (DITTO hallucination, The Thing's instability,
  Relinquished's retaliatory reflection); a "clean" transceiver output would betray the design.
- Every absorbed sample carries **lineage** (id, epoch, fidelity, parent). The stream is a
  lineage, not a loop.

---

## Design corpus (source of truth)

- Purpose / omega: `docs/logos/telos.md`, `docs/logos/pragma.md`, `docs/logos/praxis.md`,
  `docs/logos/receptio.md`, `docs/logos/alchemical-io.md`, `docs/the-universal-synthesizer.md`
- Sampler / absorption: `docs/design/alchemical-synthesis-Anthropomorphized-Sampler-Creatures.md`,
  `…-Fidelity-Stacking-Synth-Design.md`, `…-Absorption-Fusion-Synth-Design.md`,
  `…-Relinquished-monster-process.md`, `…-Modular-Synth-Absorption-Design.md`,
  `…-Modular-Synthesizer-Design.md`, `…-Ditto-Design.md`, `…-Agent-Smith-Synth-Design.md`,
  `…-Digital-Clones-Design-Guide.md`
- Surfaces / market: `docs/surfaces/market.md`, `docs/surfaces/academic.md`
- Shipped Listen increment: `forge/tune.py`, `stations.json`, `make tune` / `make stations`
