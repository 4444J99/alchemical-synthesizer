# Song Assimilation Implementation Plan

> Execute inline using superpowers:executing-plans; independently review the final
> change. User authorized selected YouTube donors and rack-wide cannibalization.

**Goal:** Preserve three selected songs, feed their audio and buffers into native
Brahma modules, and make audible, source-bound comparisons of module behavior.

**Architecture:** Extend Forge, the existing ingest/render owner. A donor manifest
holds original identity plus normalized audio. A source-derived module catalogue
discovers native SynthDefs and their actual audio/buffer/control interfaces.
Headless SC renders use the existing DSP definitions; a local audition page links
original passages and module outputs, with explicit failure/unsupported results.

**Tech stack:** Python standard library, FFmpeg, yt-dlp, sclang/scsynth NRT, HTML.
**Spec:** `docs/design/song-sampling-album-workflow.md` and the user's 2026-10-26
instruction: throw a song into the system for all modules to cannibalize.

## Decisions and bounds

- Selected recordings: Bruce Springsteen - Backstreets; Red Hot Chili Peppers -
  Blood Sugar Sex Magik (title track); Dusty Springfield - Son of a Preacher Man.
- Retain full downloaded originals under ignored `forge/out/song-sources/`.
  Never commit source audio, derived copyrighted audio, or private download data.
- Reuse the current owned worktree; new branch feat/song-assimilation-20261026
  starts at verified PR #98 head 2822695. Preserve all other worktrees/stash.
- Default audition is a bounded excerpt; full-song renders are an explicit CLI
  duration option. Sequential native processes, hard deadlines, no hardware boot.
- Reuse native SynthDefs; do not emulate named modules with generic browser FX.
- Source consumers use private mono/stereo buffers and input buses. Non-audio
  utilities retain an explicit role/result rather than pretending to be effects.
- Do not label successful acquisition, compilation, or an existing output file as
  successful processing. Validate output duration and non-silence; record failures.

## Review focus

Original/source basename collisions; corrupt or excessive-duration media;
SC string/code injection from paths; source-writing buffers leaking between
modules; partial native renders falsely accepted; catalogue coverage gaps.

## Task 1: Preserved donor admission

- [x] Resolve the user's recordings and download bounded audio with provenance.
- [x] Add failing tests for safe source admission, hashes, unique destinations,
  module extraction, and interface classification.
- [x] Implement `forge/assimilate.py` donor admission and native catalogue.
- [x] Verify originals remain unchanged, normalized files are valid; commit.

## Task 2: Native module audition

- [x] Add native regression fixtures for buffer and stream consumers.
- [x] Implement native score generation using existing SynthDefs, separate buffers,
  ordered source/module/master buses, limited output, and bounded render lifecycle.
- [x] Generate per-module status and a local audition index; expose failures.
- [x] Render the selected donors through native modules and measure outputs.
- [x] Run implicated regression suites and review; fix substantive defects.

## Task 3: Durable handoff

- [x] Document commands, exact module coverage and remaining live/UI integration.
- [ ] Publish code/tests/sanitized evidence as a PR; retain private songs/results.
- [ ] Verify local/remote head parity and clean tracked state.

## Acquisition evidence

All three bounded yt-dlp invocations exited 0 on 2026-10-26. Source IDs:
USQ697oqkaw, umopTKfas5g, ZSEKX8GAEYY. Private acquisition logs and metadata are
under `forge/out/song-sources/20261026-selected/`. Final processing results are recorded in `.codex/plans/2026-10-26-song-assimilation-verification.json`.

## Review and validation

Independent review identified stereo input downmixing, donor-independent generator
outputs, and colliding envelope/event control outputs. All three were accepted and
fixed with targeted regression coverage. Native integration exercised ten module
paths, including stereo reconstruction, buffer readers, controls, generators, and
the repaired spectral filter. Sixteen tests passed; strict smoke passed 86 checks.
Browser observation verified catalogue/filter behavior, actual WAV playback, and
single-player exclusivity. Native DSP shutdown and oversized compiler-function
failures found during development were fixed without disabling installed plugins.
