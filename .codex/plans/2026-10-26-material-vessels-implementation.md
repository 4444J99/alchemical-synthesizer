# Material Vessels Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans, test-driven-development, and one fresh whole-branch review.

**Goal:** Make shared material composition and solid/liquid/gas state change native organism processing, expose it through transparent vessels and dry/processed comparisons, and preserve the complete playable recipe.

**Architecture:** Extend the existing instrument and Forge render service. A source-owned material library defines normalized artistic properties and explicit per-organism mappings to real native controls. Browser, Node and Python validate the same state; resolved controls and material provenance travel with each rendered source. Every native definition remains in the catalogue, including unsupported material mappings and coordinated lifecycle requirements.

**Tech Stack:** Existing vanilla JavaScript, Node/Express, Python and SuperCollider; no new dependencies or services.

**Spec:** `docs/design/mimicry-material-universe.md`, approved by the user's “work that out and implement” continuation.

## Global Constraints

- Preserve original donors, saved projects, prior takes, source hashes and distinct organism identities.
- Material phase is separate from oscillator phase and the existing compositional arc.
- Default editing is per vessel; a mixture contains up to four named materials with positive fractions summing to one.
- Water, silica, iron and air provide a first editable palette; properties and mappings are artistic models, not scientific simulation claims.
- Native rendering remains bounded, serial and authenticated; the current loop continues until a completed result is applied.
- Existing projects/recipes without material state continue to work. Unknown versions, materials and profiles fail explicitly.
- Do not claim full original mimicry behavior from a non-silent render or parameter response.

## Review Focus

- Invalid composition, nonfinite numbers, unknown versions and unsupported module mappings must preserve the current sound.
- Changing tracks, sources, modules or material during a render must fence stale results.
- Save/reopen must retain mixture, phase, base and effective controls without altering original audio or the compositional arc.
- Browser preview, service and Python renderer must resolve identical controls and receipt provenance.
- Silent/identical output and missing native capabilities must stay visible; comparison does not silently normalize them into success.

### Task 1: Shared material model and native receipts

**Files:** Create `forge/materials.json`, `forge/materials.py`, `brahma/web/public/instrument/material-model.js`; modify `forge/native-controls.json`, `forge/assimilate.py`, `brahma/web/lib/native-samples.js`, `brahma/web/server.js`; tests in `tools/tests/test_materials.py` and `brahma/web/test/materials.test.js`.

**Interfaces:** `validate(state)` returns canonical `brahma.material-state.v1`; `resolve(module, baseParams, state)` returns canonical material state, resolved properties and bounded effective controls. Python exports the same functions. `describe(module)` returns mapping support and intended control effects. Native requests optionally carry `material`; receipts retain `baseParams`, effective `params`, material state and model hash.

- [x] Write tests for composition/phase validation, deterministic cross-runtime resolution, unsupported mappings and unchanged amount-zero controls; watch RED.
- [x] Implement the common palette/properties and mappings for core organisms and the existing sampler/native controls. Map only actual used DSP controls; keep other definitions visibly unsupported.
- [x] Pass material state through CLI/service rendering and validate the exact completed receipt before applying it. Run model, service and Python suites; commit.

### Task 2: Portable vessels and a working instrument surface

**Files:** Modify `sample-project.js`, `sample-controls.js`, `native-controls.js`, `sample-audio.js`, `instrument/index.html`; create `material-controls.js` and `material-vessels.css`; extend project and browser tests.

**Interfaces:** Optional project `vessels[5]` stores `{module, params, material}` per track. Native recipes optionally store `{material, baseParams, modelSha256}` alongside effective controls. `Renderer.level(track)` reads actual playing audio for the glass display. Native controls consume/restore selected vessel settings and expose dry/current comparisons without replacing sources.

- [x] Write failing save/reopen, malformed-state and real-browser material/track-fencing tests.
- [x] Add mixture/phase/amount controls, readable effective-control previews, transparent vessel rendering tied to actual waveform/level, and original/processed audition actions. Keep draft versus applied material state explicit.
- [x] Restore vessel settings on track/project changes; fence pending renders on edits. Verify old projects, sound continuity, stop/cancel and exported audio. Run suites; commit.

### Task 3: Module comparison and observed acceptance

**Files:** Create `forge/compare.py`, `tools/tests/test_material_comparison.py`; extend native catalogue UI and `forge/ASSIMILATION.md`; record sanitized evidence in this plan's results document.

**Interfaces:** Comparison consumes existing audition manifests plus an explicit source, runs native baseline/material phases through the same renderer, and writes a self-contained listening index and JSON ledger. The ledger lists every catalogue definition and separates signal response, material mapping support and original-behavior acceptance.

- [x] Write failing tests for source/hash mismatches, missing results, silence, bounded waveform comparisons and complete catalogue disposition.
- [x] Implement bounded serial comparisons, source-bound measurements and listening links; never treat waveform difference as proof of full mimicry.
- [x] Run native comparisons with synthetic probes and a retained selected-song excerpt; exercise the actual browser, save/reopen and export. Run web/Python suites and implicated native smoke checks.
- [ ] Obtain one fresh whole-branch review, fix significant findings with regression tests, commit/push the implementation and a reviewable PR stacked on #101. Retain all private sound artifacts.

## Execution record

Existing isolated checkout and clean branch verified; new branch starts at `008209240bb4d97363957f329219b434e74a9562`. `origin/main` is an ancestor. No other checkout holds this branch. Host pressure observation reports swap pressure in advisory/observe mode; native renders and browser verification will run serially with existing deadlines and budgets. No other writer's worktree or process is changed.
