# DISCOVERY - organvm/audio-synthesis-bridge

**Verdict:** VALUE FOUND -> promote into the ranked tier.
**Date:** 2026-07-01 (auto-discovery)

## Value Thesis

`audio-synthesis-bridge` is the estate's latent audio output adapter: the smallest reusable layer that can turn ORGAN-II generative structure, live audience state, or demo control streams into audible browser and SuperCollider performance. Its README still describes a larger SDF-to-synthesis architecture that is not implemented, and several planned submodules are zero-byte placeholders, so the current value is not a complete semantic music runtime. The real value is narrower and concrete: the package already exports a tested TypeScript `OscReceiver`, `WebAudioEngine`, and `SynthVoice`; the SuperCollider folder already contains a three-layer performance engine plus a documented `/ope/state` OSC schema for intensity, density, pitch, participants, and variance; together those pieces can become the shared "make this generative organ audible" spine for pitch demos, interactive installations, synchronized audiovisual pieces, and commissioned performance artifacts across ORGAN-II. That is a real reusable capability and a credible revenue path through demos/installations, not an archival stub, but it should be promoted only with the next build-out focused on proving one end-to-end adapter rather than broadening the architecture.

## What It Already Does

- Exports `OscReceiver`, `WebAudioEngine`, and `SynthVoice` from `src/index.ts`.
- Parses simple OSC-like address/value strings, dispatches handlers by address, and tracks receiver lifecycle.
- Allocates deterministic polyphonic WebAudio voice objects with defensive parameter/config copies and max-voice enforcement.
- Ships SuperCollider synth definitions for drone, granular, rhythm, and test layers.
- Ships a SuperCollider OSC receiver for `/ope/intensity`, `/ope/density`, `/ope/pitch`, `/ope/state`, `/ope/participants`, `/ope/mute`, and `/ope/heartbeat`.
- Has Vitest coverage for OSC parsing/dispatch, voice allocation/release, active voice counts, and the minimal OSC-to-voice bridge.

## Single Best Concrete First Task

Implement a tested `OpeStateMapper` that converts one normalized state object `{ intensity, density, pitch, participants, variance }` into both (a) the SuperCollider `/ope/state` OSC payload documented in `supercollider/osc_receiver.scd` and (b) equivalent `WebAudioEngine` voice parameter updates; export it from `src/index.ts`, add fixture-driven Vitest coverage, and document the one-command local demo path. This turns the repo's current loose pieces into one provable end-to-end audio adapter while keeping the future SDF architecture as a later layer.
