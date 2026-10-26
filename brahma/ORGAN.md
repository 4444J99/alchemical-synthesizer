# 🜔 Brahma — the substrate

**Kind:** shared library (not a product). **Lane:** `feat(brahma):`.
Registered in [`../ORGANS.md`](../ORGANS.md).

The alchemical synthesizer itself — the instrument this whole repo grew from. It
absorbs, mutates, and re-expresses the identities of other systems through a
strict 7-stage biological signal path (Assimilation → Gating → Binding →
Extraction → Transmutation → Protection → Release).

## What it owns (this directory)

| Path | Role |
|------|------|
| `sc/` | SuperCollider — the DSP engine + NRT renderers (`13_nrt_renderer.scd`, `14_stem_voices.scd`). |
| `pd/` | Pure Data — performance UI / visual patching (optional). |
| `ableton/` | Ableton Bridge (Extensions SDK) — `manifest.json` + activation/release. |
| `web/` | Visual Cortex, Golem/Canvas interfaces and live workbench; Node.js 24 gateway and browser tooling. |

## Boundary

- The synthesis substrate lives in `sc/`, with Pd/Ableton interfaces alongside it.
  **Forge** consumes its NRT renderers and browser visual assets.
- The web gateway has explicit integration points: it calls Forge's render and
  analysis tools and serves `aether/web/listener/` at `/aether/`. Those files keep
  their lane ownership.
- **AETHER** may use local Forge/Brahma NRT, but its current container copies only
  AETHER source and renders donor/tone fallback audio. It does not bundle `web/`.
- Adding a creature, an operator, or a Visual-Cortex vessel is a Brahma change,
  even when a Forge or Aether feature motivated it.

## Acceptance and remaining work

The 2026-10-25 local pass verified six native DSP groups and ten browser checks.
The [native harness](../tools/dsp/README.md) covers compilation, bounded output,
sample measurements, contracts, truthful telemetry and an isolated dummy server.
Class files must be installed/recompiled before `sc/loader.scd` loads scripts.
The full-loader attempt on headless Linux remains blocked by ALSA MIDI sequencing;
these checks do not establish whole-rack routing or physical-device acceptance.

Live organism capture is not connected to measured traits. Missing measurements
are unavailable and synthetic telemetry is labelled. Tidal/Sonic Pi composition
and execution adapters are unimplemented; installation discovery is separate from
availability. The prioritized next work is in [ROADMAP.md](../ROADMAP.md#current-acceptance--2026-10-25).
