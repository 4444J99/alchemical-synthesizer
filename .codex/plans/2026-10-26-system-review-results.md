# Alchemical Synthesizer system review

Reviewed 2026-10-26 against implementation e27f020306273c697a6c7909ca1c7c4e3ea5e9c2.
The review branch adds documentation and evidence only.

## Conclusion

The existing Forge pipeline can ingest audio, make approximate stems, recombine
them, and render real sound through Brahma. The requested playable song-sampling
workflow is not complete: source loading, sample bindings, usable slice editing,
durable sessions, and the browser instrument's engine connection need integration.
Passing tests establish the scopes below, not complete musical or live acceptance.

The original request is applied as repository verification and housekeeping plus
a concrete integration direction for sampling songs into album material. See
[song-sampling design](../../docs/design/song-sampling-album-workflow.md).

## Findings, ordered by impact on the requested workflow

1. **The browser instrument does not sample imported songs.**
   `brahma/web/public/instrument/instrument.js` creates oscillators in its local
   adapter. Its OSC adapter sends `/brahma/instrument/note`; no corresponding
   receiver exists in the checked-in SuperCollider source. The authenticated
   workbench uses the distinct `/brahma/live/play` contract. Connecting a WebSocket
   does not prove that the older instrument reaches the engine.
2. **Engine sampling primitives exist but lack the source-loading connection.**
   `brahma/sc/25_elektron_octatrack.scd` has a looper, time-stretch voice, slicer,
   and `/octahedron/slice` responder. Its `sliceBuf` starts nil; the inspected
   source contains no assignment connecting an imported song to it. Existing
   sampler creatures and offline stem voices are reusable, not a finished library.
3. **Freeze is not a saved project.** The instrument freeze handler logs the grid
   to the browser console and updates a button. It does not persist source audio,
   slice boundaries, patterns, routing, or a reopenable session. Scene hashing in
   `pattern.js` is useful but is not persistence.
4. **Foundry can falsely label a render as live.** In
   `product/src/core/engine.js`, opening the local OSC listener sets `online=true`;
   successful UDP send then sets `simulated=false` and an audio URL. A probe with
   no engine peer, a private local receive port, and send port 59999 reproduced
   `online=true`, `simulated=false`, `audioUrlPresent=true`. No checked-in
   `/brahma/foundry/render` receiver was found. Require engine availability and a
   render completion/file receipt before presenting available audio. This defect
   remains open; the existing Foundry smoke suite does not detect it.
5. **Input safety and album identity need work before batch ingestion.**
   `forge/ingest.sh` and `rip.py` choose destinations from names and use overwrite
   operations. `forge.sh` constructs recipe JSON by string interpolation, so
   arbitrary quote/backslash characters in names or paths need regression coverage.
   Use stable source IDs, retain originals, and distinguish clips from whole stems.
6. **Authoritative documentation has drifted.** `ORGANS.md`, `aether/MANIFEST.md`,
   `forge/ORGAN.md`, and portions of `ROADMAP.md` retain paths from before AETHER
   consolidation (`deploy/aether`, root `tools/broadcast.sh`, `forge/tune.py`).
   Current implementation uses `aether/deploy`, `aether/tools`, and
   `aether/web/listener`. Historical roadmap checks are not fresh runtime proof.

## Verification performed

| Surface | Current result | Limit of this evidence |
| --- | --- | --- |
| Brahma web unit/integration tests | 151 passed | Provider execution and artistic quality not established |
| Security regressions | 12 passed | Scope is the existing regression set |
| Foundry smoke | 21 passed | Includes stub billing and fixture audio; false-live defect above remains |
| AETHER HTTP/path tests | 2 passed | No new hosted deployment |
| Python tooling | 7 passed | Packaging and native runner regressions |
| Native SC phase_a, class_runtime, flucoma_buffer | All three passed | Selected native tests, not every SynthDef or a full live performance |
| Whole-repo strict smoke | 75 passed, 0 failed, 0 skipped | Includes structure and syntax checks as well as runtime checks |
| Browser workbench | 4 passed | Real browser/gateway; UDP receiver substitutes for SC in this test |
| Forge ingest, approximate split, recipe | All passed | Synthetic fixture; ffmpeg split is explicitly approximate |
| Single-voice NRT render | Non-silent; peak -2.33 dBFS, RMS -12.64 dBFS | Four-second synthetic source, not listening acceptance |
| Per-stem NRT render | Non-silent; peak -6.49 dBFS, RMS -22.48 dBFS | Four-second synthetic source; default creature mapping |

Both measured renders were about 4.60 seconds including the renderer's tail.
Test dependencies installed from lockfiles in the isolated review checkout.
Checks ran serially with individual hard deadlines and lower process priority.
No original media, paid provider, broadcast, deployment, or billing action used.

Evidence:
- [System verification](2026-10-26-system-verification.json)
- [Forge audio verification](2026-10-26-forge-verification.json)
- [Git reconciliation](2026-10-26-git-reconciliation.json)

## System boundaries and unmeasured surfaces

Brahma owns the DSP engine, Pure Data/Ableton adapters, web instrument/workbench,
and agent control. Forge owns file ingestion and production. AETHER owns broadcast
and downstream distribution. Foundry is the product/API surface in `product/`.
The sample engine belongs to Brahma; preparation and track rendering belong to
Forge. Sampling an album does not require activating broadcast or commerce.

Pure Data's device/UI behavior, a real Ableton host session, every SC module,
hardware audio routing, full Demucs separation, paid AI-provider calls, video
export, standalone AETHER extraction, and current hosted radio operation were
not exercised in this pass. The existing Ableton bridge smoke did pass inside
the 75-check suite. No broad live or end-to-end acceptance claim is made.

## Local and remote reconciliation

- Canonical main was clean and equal to fetched origin/main at e27f020.
- Existing PR #94's exact head f907585 is recorded merged into e27f020; ancestry
  was checked against fetched main. No open PR existed at intake.
- Latest main CI, CI Minimal, and Pages deployment runs reported success.
- All local branch commits were reachable from fetched remote refs. Remote prune
  dry-run found no stale tracking references. This is publication evidence, not
  proof that a squash merge preserves every checkout artifact.
- At the later inventory: 22 local branches, 46 remote branches, three worktrees
  including this review, and one retained stash. Seventeen local branch heads
  matched merged PR heads. Exact identities are in the JSON receipt.
- Two pre-existing worktrees disappeared between inventories through another
  actor. This session did not delete them or claim their retirement evidence.
- The remaining prior verification worktree and stash are retained. Ignored
  private state, process ownership, and retirement custody have not been proven;
  no destructive cleanup or reset was performed by this review.

## Next owned work

Use the song-sampling design's first acceptance slice for implementation. Address
the false-live render status before trusting Foundry as an audio-completion
surface. Reconcile stale boundary documentation and preserve identities when
hardening ingestion. Keep the prior verification owner (#93) open; this review
does not close human-owned work or claim repository retirement complete.

Published owners:
- Sampling integration: https://github.com/4444J99/alchemical-synthesizer/issues/95
- Foundry render truthfulness: https://github.com/4444J99/alchemical-synthesizer/issues/96
