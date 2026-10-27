# Native DSP predicates

Run from repository root with Python 3.11+ and SuperCollider 3.13+ (`sclang` and
`scsynth` on PATH, or a standard macOS application bundle):

```bash
python3 tools/dsp/test_dsp.py
```

This runs seven native predicate groups and explicitly skips the opt-in live-buffer
and voice-lifecycle group. Missing native tools fail setup rather than masquerading
as a passing parse check. The harness isolates the SC class library and temporary
outputs. On Linux it configures headless Qt; root-only Qt sandbox disabling applies
only to these trusted local test scripts.

For all eight groups on Linux, install `jackd2` and run:

```bash
BRAHMA_DSP_DUMMY_AUDIO=1 python3 tools/dsp/test_dsp.py
```

The harness starts a uniquely named JACK dummy backend with no hardware fallback,
then shuts down only its own process group. It tests asynchronous buffer measurement,
repeated-note release tails, voice limits, panic, and live gateway reporting.

| Predicate | Evidence |
|---|---|
| Class and script compilation | All nine repository classes compile and every `.scd`, including nested tests, parses |
| Governor NRT | Stereo output stays within 0.90001; runaway channel is quarantined and safe channel passes without dry duplication |
| Metrics | Stationary/changing tones, noise, aligned correlation, silence, invalid and insufficient input |
| Telemetry | Uncaptured measurements are unavailable; demo telemetry is explicitly labelled |
| Contracts | JSON decoding, required dictionaries, dotted ranges, canonical bounds, normalization and invalid contracts |
| Dummy-server integration | Real SC buffer reads and voice lifecycle without a physical audio device |
| Upstream measured traits | Actual `phase_a.scd` assertions execute, including scalar schemas and FSAP measurement admission |
| Upstream class runtime | Actual `class_runtime.scd` assertions execute, including provenance, transmutation proof invalidation and bridge expiry |

The class API (`BrahmaMetrics`) and phase-11 collector share one bounded core
implementation and one Buffer-read owner. All default metrics retain the definitions
above when optional FluCoMa is installed. `BrahmaMetrics.fluidCoherence` is a separate,
explicit optional algorithm; its real plugin test is not part of the core-only gate
and is not claimed as verified here. Missing FluCoMa makes that explicit test fail.

Installation and native-runner lifecycle predicates:

```bash
python3 -m unittest tools.tests.test_sc_install tools.tests.test_sc_runner -v
bash tools/install-brahma.sh --extensions-dir /path/to/test/extensions
```

Use a temporary extension directory for isolated verification. The normal installer
uses the platform user directory, links the complete recursive class tree, removes
only legacy symlinks to this same source, and refuses foreign collisions before any
change. The verifier starts a bounded native file driver using supported `-l`
configuration; it does not use `sclang -e`.

Compilation does not execute every module. These predicates do not prove full-loader
boot, routing across the whole rack, physical MIDI/Pd/Ableton behavior, perceptual
fidelity, or artistic acceptance. The headless full-loader attempt in the review
was blocked by unavailable ALSA MIDI sequencing. See the
[review](../../docs/reviews/2026-10-24-verification-hardening.md).
