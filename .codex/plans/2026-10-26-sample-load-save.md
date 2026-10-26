# Sample Load and Save Implementation Plan

> Execute inline using superpowers:executing-plans. User authorized implementation
> on 2026-10-26 after the system review. One independent branch review at the end.

**Goal:** Load real local audio into the existing browser instrument, play and
sequence editable chops, and save/reopen a portable project containing the audio.

**Architecture:** Add a dependency-free project model beside `pattern.js` and a
WebAudio sample renderer shared by live and offline playback. Extend the existing
instrument UI. Local file bytes are embedded in a versioned project JSON; nothing
is uploaded. Decode and validate a loaded project completely before replacing the
current session. Preserve the existing synthesis and OSC choices.

**Tech stack:** Browser WebAudio/File APIs, vanilla JavaScript, Node tests,
Puppeteer using the existing installed Chrome and gateway.

**Spec:** `docs/design/song-sampling-album-workflow.md`, first browser load/save
slice. Owner: #95. Base: 9e4a82bdc283bfe268f35985f1a4126b50f620ee.

## Constraints and scope

- Reuse this session's isolated checkout; branch feat/song-sample-projects-20261026.
- Keep source audio local; preserve input files and prior downloaded projects.
- Eight initial chops per source, editable start/end boundaries in seconds.
- Save source SHA-256, bytes, slices, track selections, patterns, tempo, phase,
  and deterministic cycle. Reopen stopped with the actual decoded audio restored.
- Defaults: 64 MiB encoded source bytes per project, 256 MiB decoded audio;
  resource limits supplied through the model/renderer configuration.
- Browser sample playback is explicit. Native SC sample transfer and Foundry #96
  remain separate; do not substitute oscillators for unavailable sample playback.
- No new dependencies, paid provider calls, hardware/audio routing, or deployment.

## Review focus

- Invalid/corrupt/oversized project must leave the current playable session intact.
- Slice references survive commands and generative redistribution.
- Duplicate source imports do not multiply audio memory or change source identity.
- Stop/reopen cancels already scheduled audio and releases its nodes.
- Save/reopen preserves bytes and settings; names and paths cannot inject markup.

## Task 1: Project and pattern contracts

Files: `public/instrument/sample-project.js`, `pattern.js`, `test/sample-project.test.js`
(all beneath `brahma/web/`).
Interfaces: `createSource(bytes, metadata)`, `validateProject(project, limits)`,
`serialize(project, limits)`, async `deserialize(text, limits)`, `equalSlices(duration, n)`.

- [x] Add failing tests for round trip/hash integrity, malformed bounds, missing
  sample references, budget refusal, and sample identity through pattern commands.
- [x] Implement validation and immutable serialization using schema
  `brahma.sample-project.v1`; preserve optional sampleId/slice in pattern cells/events.
- [x] Run `node --test --test-concurrency=1 test/sample-project.test.js`; commit.

## Task 2: Real browser playback, editing, and portable sessions

Files: `public/instrument/sample-audio.js`, `instrument.js`, `index.html`,
`test/e2e/instrument.e2e.js`.
Interfaces: renderer loads source bytes into AudioBuffers, triggers bounded slice
voices, cancels active voices, and renders an offline loop through the same path.

- [ ] Add browser regressions for importing a synthetic WAV, editing a chop,
  sequencing it, saving, reopening, corrupt-project rollback, and audible WAV export.
- [ ] Run against the old UI and record expected failures before implementation.
- [ ] Implement source/track selection, waveform/chop controls, audition, save/open,
  status/error feedback, transactional restore, and loop WAV export.
- [ ] Verify real rendered sample signal, not oscillator fallback; verify stop.
- [ ] Run browser tests, web suite, pattern self-test, and strict smoke; commit.

## Task 3: Review and publication

- [ ] Independently review the complete implementation; fix substantive findings
  with regressions and preserve a concise execution record below.
- [ ] Publish feature branch and a PR with #95, exact scope and verification.
- [ ] Verify clean local state and exact remote head; retain worktree and samples.

## Execution record

- Existing baseline: 151 web tests, 4 browser workbench tests, 75 strict smoke
  checks, and native/render checks passed in the preceding review turn.
- Ruling: proceed with browser-local load/save first, as authorized by the user;
  native sample-buffer transport is explicitly unfinished. Cost: SC-only sampling
  requires the next integration slice, while this flow remains usable locally.
- Task 1: seven regressions failed before implementation. Project and pattern
  contracts now pass; full web suite 158/158. Fixture hash corrected against
  independent Python hashlib output (last character was transcribed incorrectly).
