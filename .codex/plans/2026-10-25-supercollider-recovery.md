# SuperCollider recovery and Brahma Phase A

User authorization: run a controlled crash test, stop the crashes, and finish the directly related OpenCode transcript tasks. No paid APIs or deployment.

1. Establish native IDE quit/relaunch behavior and isolated sclang boot/exit on an unused UDP port. Preserve existing sessions; never inject malformed packets into the user interpreter. Distinguish reproduced crashes from historical traces.
2. Install the official FluCoMa Mac binary package, verify SHA256 and architecture, then verify language classes and a real silent server-side operation. Preserve both macOS and XDG extension paths.
3. Reproduce the committed SC metric/contract defects with real sclang tests. Correct asynchronous buffer access, spectral stability/entropy, multichannel fidelity, measured-confidence validation, and substrate contracts. Keep existing scalar/sample callers compatible; use callbacks for server buffers.
4. Add a bounded diagnostic/test runner and accurate setup documentation. Verify unknown/invalid inputs and low confidence fail closed; distinguish numeric trait values from confidence.
5. Run implicated native and web tests serially, review, commit/push a PR, and record runtime observations and outstanding work in this plan.

Constraints: existing execution lease codex-supercollider-01a172f6; one serial low-impact process, short deadlines and nice priority. Heavy work remains disallowed unless separately admitted. Attempt ends by 12:44 UTC.

Review focus: asynchronous Buffer reads, missing dependencies, empty/nonfinite signals, stereo correlation, no silent acceptance of unknown contracts. Spectral entropy uses spectral magnitudes (not spectral shape moments, which do not encode the distribution).

Baseline: clean origin/main 24651b0693808bd91836ab2013ad1f5f357a1d41; isolated branch fix/supercollider-recovery-20261025. Native IDE had a blank document and active interpreter; no scsynth or local OSC bridge found on standard ports. First ordinary Quit/relaunch produced no new crash report.

## Implementation ledger

- Root cause reproduced: malformed packet caused SIGABRT / `Bad OSC message size` in disposable child on random port53992. Found the actual raw `x` probe in `sandbox.selfTest`, called with the live engine port by `server.initSandbox`. Corrected probe regression failed before fix, then 24 sandbox checks passed. The corrected probe left both disposable and IDE interpreters active.
- A1: official1.0.10 package checksum/arm64 verified; installed one copy and XDG symlink. Real server plugin processed buffer and printed1.0.10 version.
- A2-A4: class compile and async Buffer access repaired; native FFT spectral entropy, FluCoMa centroid stability with padding0, per-channel positive correlation. Native sample and server-Buffer tests pass.
- A5: measured provenance/reconstruction-confidence threshold wired into FSAP; native tests reject low-confidence maps and accumulate high-confidence measured maps.
- A6: four JSON substrate schemas loaded by SC and the browser from one shared registry. Idea contract validates natively.
- Additional demonstrated defect: headless sandbox eval collided with IDE57120, auto-incremented to57121, then spun on sandbox receive denials. Explicit private inbound port preserves57120 egress; conformance changed from failure to10/10 passing.
- Ruling: spectral entropy comes from the spectral distribution, not spectral-shape moments. Shared JSON schema loading does not assert a live SC-to-browser measurement feed. Full Phase B trait derivation and transmutation are outside this directly related Phase A recovery.
- Historical Qt/Cocoa cleanup crashes remain unreproduced; no system accessibility capability or saved session was removed to manufacture a pass.

- Fresh whole-branch review completed. Fixed all four important findings: stereo frame cap, symbolic/nonnumeric schema values, absent/contradictory measured evidence, and native-runner output bound. Added regression checks; runner flood test changed from exit0 to bounded exit125. Explicit numeric non-audio axes reject dictionary values as well as strings/symbols. Full live trait extraction is not claimed.
- Web suite:146/146 passing, zero skipped. Real FluCoMa Buffer tests pass, including the stereo8192-frame cap. Native scalar/contract/FSAP suite passes.

## Installed runtime and retention

The repaired classes are installed through source links in both native/XDG extension roots. The IDE recompiled422 files successfully and evaluated `[FluidBufSpectralShape, AdamKadmon, BrahmaMetrics]` to all three class objects with Interpreter Active. The diagnostic runner avoids adding a duplicate include path when those same source classes are already installed.

Retain this worktree: installed Brahma class links depend on it. Branch and all source artifacts are pushed; PR84 owns integration. No raw transcripts, package binaries, runtime tokens, or crash reports are committed. The report supplied at08:38 describes PID42666's08:22:25 crash, before the fix, not a new post-fix failure.
