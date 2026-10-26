# Playable Song Sketch Implementation Plan

> Execute inline with superpowers:executing-plans. One independent final review.

**Goal:** Deliver a saved, playable Son of a Preacher Man sketch with eight chops,
native transformations, Golem drum sounds, reopen fidelity, and measured WAV export.

**Architecture:** Reuse SampleProject/SampleAudio/Pattern for sequencing and save.
Reuse Forge's native donor renderer behind an authenticated local async endpoint.
The browser renders a selected sound in the background, then changes future notes
without resetting transport. Source and transformed audio plus recipe provenance
remain embedded in the portable project. Forge generates the private starter sketch.

**Tech stack:** Existing Python, FFmpeg, sclang/scsynth NRT, Express, browser JS.
**Spec:** `docs/design/song-sampling-album-workflow.md`, existing issue #95, and the
user's 2026-10-26 approval of the three-step playable-sketch milestone.

## Decisions and bounds

- Continue in the session-owned retained worktree on new branch
  `feat/playable-song-sketch-20261026`, based on PR #99 head `60d7ec7`.
- Background native render/apply is the implementation choice. It reuses measured
  DSP and avoids opening hardware; the UI names render latency explicitly.
- Existing real-time SC/OSC remains visible. This work does not equate rendered
  native sample playback with a running hardware rack or claim musical acceptance.
- Native render requests require the existing human role, same-origin loopback,
  finite parameter ranges, PCM source admission, one active process, bounded wall
  time/output/storage, and retained private results. No arbitrary paths or SC code.
- The module catalogue retains all roles. Expose safe controls for the existing
  sampler creatures, slicer/time-stretch, and selected effects; other eligible
  native paths remain available at their defined defaults, with role labels.
- Originals and previous takes are retained. Private media stays under forge/out;
  Git holds implementation, synthetic tests, recipes, and sanitized verification.
- A playing loop retains tempo, step/cycle, and existing sounding voices when a
  replacement becomes ready. Stop/open/source change invalidates a pending apply.

## Review focus

Late native responses after Stop/open/source change; malformed PCM and nonfinite
parameters; loopback/Origin/role authorization; misleading successful output without
manifest/hash validation; full project quotas during repeated edits; recipe/source
references after save/reopen; active child termination and concurrent admission.

## Task 1: Parameterized native render service

Files: `forge/assimilate.py`, `forge/native-controls.json`, new
`brahma/web/lib/native-samples.js`, `brahma/web/server.js`, native tests.

- [x] Add failing tests for parameter validation, request/auth/PCM admission,
  native result hashes, concurrency, and failures.
- [x] Add safe native control metadata and CLI parameter overrides; preserve all
  module catalogue roles and prevent bus/buffer overrides.
- [x] Implement authenticated local jobs and private result retrieval, bounded
  child execution and cancellation; verify native synthetic render end to end.
- [x] Commit after implicated Python and Node contracts pass.

## Task 2: Instrument native controls and portable recipes

Files: existing `sample-project.js`, `sample-controls.js`, `instrument.js`,
`index.html`; new `native-controls.js`; browser/model tests.

- [x] Add failing save/reopen and browser tests for transformation application,
  retained originals, stale responses, and unchanged playing transport.
- [x] Add safe recipe/source validation and transformation selection/controls,
  authenticated session handoff, background render status and cancellation.
- [x] Apply transformed source to future notes on the selected track; preserve
  source chops and unrelated tracks, restore original on request.
- [x] Verify playback, Stop, save/reopen, offline export and rejection behavior;
  commit with meaningful browser regression evidence.

## Task 3: Saved musical sketch and publication

Files: Forge sketch builder, synthetic contract fixtures, README/design updates,
sanitized evidence under `.codex/plans/`; private artifacts under `forge/out/`.

- [ ] Build eight donor chops plus a small native palette and render actual
  Golem kick/snare/hat presets from their existing source definitions.
- [ ] Create a 32-step, five-track starter project with a modest editable groove;
  save/reopen and export through the real browser instrument.
- [ ] Measure source/output integrity, duration/non-silence and reopen fidelity.
- [ ] Run scoped regressions, one independent review, resolve substantive issues.
- [ ] Commit/push code and evidence as a stacked PR; verify remote parity and
  retain private project/audio in the session-owned checkout.

## Preflight

Current worktree is isolated and clean at `60d7ec7`; origin/main has no missing
commits (0 behind, 13 ahead). Host admission reports observed swap pressure; mode
is observe. No lease names this checkout. Work stays bounded and serial for native
processing. An existing unrelated server on 49374 is not this checkout; no Brahma
server is active for this lane. No other checkout or branch will be modified.
