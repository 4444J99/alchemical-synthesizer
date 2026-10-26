# SuperCollider and FluCoMa setup

Use the official prebuilt FluCoMa package, not the nonexistent `flucoma/fluid-ugens` URL. Download the Mac DMG from https://github.com/flucoma/flucoma-sc/releases/latest and copy `FluidCorpusManipulation` to the directory returned by `Platform.userExtensionDir.openOS`.

In the IDE, choose File > New, type code in the editor, and evaluate with Command-Return. The Post Window only displays results. Recompile through Language > Recompile Class Library. Never use the previous logout AppleScript.

This host has two extension roots: `~/Library/Application Support/SuperCollider/Extensions` for native launches and `$XDG_DATA_HOME/SuperCollider/Extensions` for XDG launches. Install one real package and link the other root to it, rather than compiling two independent copies. FluCoMa 1.0.10's Mac package is universal arm64/x86_64; its SHA256 is `1b37598708f2f033f67be15cc4ce375d230d9af6dba76fde175c593c0f4b1c06`.

Expose the repository's SC classes without copying generated source:

```sh
python3 tools/install-brahma-classes.py
python3 tools/install-brahma-classes.py --apply
```

The installer previews changes unless `--apply` is supplied. It links the complete recursive class tree and removes only legacy per-file symlinks that resolve to this same source. Foreign files or links stop the operation before changes. Keep the source checkout available. `bash tools/install-brahma.sh` applies the installation and verifies all classes with a bounded native file driver; `--no-recompile` skips that verification. Use `--extensions-dir PATH` for a deliberate nondefault extension directory.

Run real native checks (not only JavaScript smoke checks):

```sh
python3 tools/test-supercollider.py brahma/sc/tests/phase_a.scd
python3 tools/test-supercollider.py brahma/sc/tests/class_runtime.scd
# Optional: requires the real FluCoMa classes and server plugin.
python3 tools/test-supercollider.py brahma/sc/tests/flucoma_buffer.scd
```

The runner discovers `sclang` on PATH or in a standard macOS bundle; set `SCLANG_PATH` to select another installation. It uses a private UDP port, an SC 3.13-compatible configuration file, bounded output and a 25-second process deadline. The FluCoMa test starts its own silent server with zero input channels, performs a real spectral analysis, and quits it. It does not play a test tone through hardware outputs. For an IDE-only dependency check, evaluate `s.waitForBoot({ FluidDataSet.version; });`.

## Measurement API

Sample collections return scalar measurements. Server Buffers are asynchronous and require an action:

```supercollider
~metric_collector.measureCoherence(buffer, { |coherence| coherence.postln });
~metric_collector.measureEntropy(buffer, { |entropy| entropy.postln });
~metric_collector.measureFidelity(inputBuffer, outputBuffer, { |fidelity| fidelity.postln });
```

The default class and collector APIs share `BrahmaMetrics`’ bounded core implementation: mean-centered Hann-windowed spectral-power centroid stability and mean Shannon spectral-power entropy. They examine at most 64 complete 1024-sample windows per selected channel. Missing, silent, invalid or insufficient samples return unavailable/nil, rather than fabricated zero. Fidelity is absolute zero-lag Pearson correlation of aligned arrays; it ignores gain, DC offset and polarity and does not correct latency or establish perceptual equivalence. The collector selects a channel (channel zero by default), while `BrahmaMetrics.fidelity(..., channels)` averages explicit channel correlations. Live acquisition coalesces per-buffer requests, caps 65,536 frames and 262,144 total samples, and expires incomplete reads. `BrahmaMetrics.read` exposes at most the first 8,192 acquired frames. Keep captured buffers stable until their callbacks complete.

Installing FluCoMa does not change those defaults. Request its distinct centroid algorithm explicitly with `BrahmaMetrics.fluidCoherence(buffer, action)`. The optional test executes the real server plugin and fails when it is missing; the core-only acceptance run does not certify that plugin path.

`attachMeasurements(traits, coherence, entropy, fidelity)` validates caller-supplied metric values, records their source explicitly and uses the documented correlation value as integration confidence. This helper does not authenticate capture identity or prove that a caller measured the supplied numbers; that link belongs to the future capture-to-artifact pipeline. `FSAP.integrate` requires measured provenance and the selected contract’s confidence threshold (0.85 by default); unknown contracts fail closed. Existing canonical trait validation still accepts nested normalized dimensions; numeric trait values such as centroid 0.2 are not confidence scores. Unknown named contracts fail closed.

The shared `brahma/substrate/{sound,idea,product,cosmos}.json` contracts are consumed by `AdamKadmon.loadContract(path)` and by the Tree through `/api/substrates/*.json`. This is shared schema loading, not a claim that non-audio traits were measured by the audio engine.

## Crash diagnosis, 2026-10-25

SuperCollider 3.14.1 aborts on a malformed incoming OSC packet with `Bad OSC message size`. Brahma's sandbox startup self-test sent the raw byte `x` to its configured engine port. That probe could kill both an IDE interpreter and another running interpreter. It now sends a padded, valid, argument-free `/brahma/sandbox/probe` OSC message while retaining all seven sandbox checks. Never probe an OSC port with raw UDP text.

A disposable interpreter reproduced the raw-packet abort. The corrected sandbox self-test passed 7/7 and the interpreter exited normally; the restarted IDE interpreter also remained active after the corrected probe. FluCoMa's actual server plugin reported `1.0.10+sha.c1ca9ec.core.sha.f1551f70` and processed an audio buffer successfully.

Earlier native IDE crashes in Qt/Cocoa cleanup were not reproduced by the normal quit/relaunch test. This patch addresses the demonstrated OSC crash trigger, not every possible Qt failure. Preserve any future crash report rather than deleting preferences, sessions, or extensions.
