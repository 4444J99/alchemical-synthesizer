# Pragma — The Concrete State

Brahma is a substantial synthesis and interface codebase whose strongest remaining
gap is a complete, measured absorption-to-artifact workflow. The source contains
more capability than its original acceptance gates exercised. The
[2026-10-24 verification review](../reviews/2026-10-24-verification-hardening.md)
separates reproduced behavior from intended behavior.

## Verified building blocks

| Area | Current evidence | Limit |
|---|---|---|
| Native SC | Class compilation and repository `.scd` parsing; focused NRT and dummy-JACK predicates | Not a full-rack hardware boot |
| IMMUNE | Protected bus is replaced; high-level input is bounded and runaway channel quarantined | Every production route/order still needs full-rack acceptance |
| Metrics | Sample-derived spectral-centroid stability, spectral-power entropy and aligned correlation | Live capture is not connected |
| Trait contracts | Canonical dictionary structure, JSON contracts, nested range validation and normalization | Structural validity does not establish perceptual fidelity |
| Workbench | Real browser → typed gateway → UDP; edit/run/stop/panic and asynchronous lifecycle checks | UDP fixture is not audible SC playback |
| Foundry | Authenticated ownership, signed payment transition, controlled audio-file serving | Creation remains simulated; production commerce lifecycle unfinished |
| AETHER | Bounded ffmpeg broadcast, host defaults, operator intake and listener/edge predicates | No actual container/cloud deployment in this pass |
| Distribution | Tracked-source packaging, rebuilt browser bundle, checksum and isolation predicates | No newly published release assets |

## Measurement semantics

`~METRIC_COLLECTOR` computes on actual sample arrays or captured buffers/files:

- **Coherence:** stability of spectral centroid over complete, active Hann-windowed
  FFT frames, normalized to `[0,1]`. It is not a universal perceptual coherence score.
- **Entropy:** Shannon entropy in bits of the one-sided spectral-power distribution,
  with a separate normalized value.
- **Fidelity:** absolute zero-lag Pearson correlation for aligned arrays. Gain, DC
  and polarity do not affect it; latency is not estimated or corrected.
- **Stress:** observed server CPU load when the server is running.

Missing, silent, invalid, or insufficient samples produce unavailable status rather
than invented numbers. Analysis is bounded to 64 windows of 1024 samples and an
explicit channel. The buffer adapter executes asynchronously.

`14_visual_cortex.scd` currently has no live capture source and reports that
measurement is unavailable. Synthetic telemetry is opt-in and labelled `DEMO`.
The trait overlay labels derived proxy values. AETHER's generative indicators
remain provisional and are separate from these DSP measurements.

## Remaining concrete gaps

The full loader reached an unguarded MIDI initialization failure on the review's
headless Linux host without an ALSA sequencer. Focused native tests use an isolated
dummy JACK server and do not erase that failure. Physical MIDI/Pd/Ableton behavior,
full routing/governor order, sustained performance and listening acceptance remain.

FSAP is not yet a verified donor → capture → analysis → transformation → release
workflow. The A/B benchmark and sine-sweep helper require repair before their output
is treated as evidence. AdamKadmon contract strictness is metadata; capability-token
signing is unavailable and its permission stub is not an authorization boundary.

Foundry does not have an acknowledged render/artifact-ingestion pipeline,
transactional multi-process storage, or subscription/refund/payout reconciliation.
Tidal and Sonic Pi discovery does not enable their unimplemented workbench adapters.

## Launch and next work

Install the `.sc` class files into the SC Extensions directory and recompile before
loading `brahma/sc/loader.scd`. The [root README](../../README.md) has prerequisites
and layered launch commands; [native tests](../../tools/dsp/README.md) provide a
hardware-free verification path. There is no accepted universal one-command launch.

[Praxis](praxis.md) orders the remaining work around one measured musical result.
