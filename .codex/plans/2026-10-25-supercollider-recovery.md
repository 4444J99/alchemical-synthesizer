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
