# SuperCollider and FluCoMa setup

Use the official prebuilt FluCoMa package, not the nonexistent `flucoma/fluid-ugens` URL. Download the Mac DMG from https://github.com/flucoma/flucoma-sc/releases/latest and copy `FluidCorpusManipulation` to the directory returned by `Platform.userExtensionDir.openOS`.

In the IDE, choose File > New, type code in the editor, and evaluate with Command-Return. The Post Window only displays results. Recompile through Language > Recompile Class Library. Never use the previous logout AppleScript.

This host has two extension roots: `~/Library/Application Support/SuperCollider/Extensions` for native launches and `$XDG_DATA_HOME/SuperCollider/Extensions` for XDG launches. Install one real package and link the other root to it, rather than compiling two independent copies. FluCoMa 1.0.10's Mac package is universal arm64/x86_64; its SHA256 is `1b37598708f2f033f67be15cc4ce375d230d9af6dba76fde175c593c0f4b1c06`.

Expose the repository's SC classes without copying generated source:

```sh
python3 tools/install-brahma-classes.py
python3 tools/install-brahma-classes.py --apply
```

The installer refuses to replace existing different content. Keep the source checkout available. Recompile the IDE after installation.

Run real native checks (not only JavaScript smoke checks):

```sh
python3 tools/test-supercollider.py brahma/sc/tests/phase_a.scd
python3 tools/test-supercollider.py brahma/sc/tests/flucoma_buffer.scd
```

Set `SCLANG_PATH` if necessary. The runner uses a private UDP port, nice priority, and a 25-second deadline. The FluCoMa test starts its own silent server with zero input channels, performs a real spectral analysis, and quits it. It does not play a test tone through hardware outputs. For an IDE-only dependency check, evaluate `s.waitForBoot({ FluidDataSet.version; });`.

## Measurement API

Sample collections return scalar measurements. Server Buffers are asynchronous and require an action:

```supercollider
~metric_collector.measureCoherence(buffer, { |coherence| coherence.postln });
~metric_collector.measureEntropy(buffer, { |entropy| entropy.postln });
~metric_collector.measureFidelity(inputBuffer, outputBuffer, { |fidelity| fidelity.postln });
```

Coherence uses centroid stability from FluCoMa, excluding synthetic padded boundary windows. A native FFT implementation supports sample collections and hosts without FluCoMa. Spectral entropy uses the magnitude distribution; spectral moments alone cannot reconstruct that distribution. Fidelity averages positive Pearson correlation per channel, so polarity inversion does not count as faithful reconstruction. Buffer reads are limited to the first 8192 frames.

`attachMeasurements(traits, coherence, entropy, fidelity)` adds measured provenance and uses reconstruction fidelity as the integration confidence. `FSAP.integrate` requires measured provenance and confidence at least 0.85. Existing canonical trait validation still accepts nested normalized dimensions; numeric trait values such as centroid 0.2 are not confidence scores. Unknown named contracts fail closed.

The shared `brahma/substrate/{sound,idea,product,cosmos}.json` contracts are consumed by `AdamKadmon.loadContract(path)` and by the Tree through `/api/substrates/*.json`. This is shared schema loading, not a claim that non-audio traits were measured by the audio engine.

## Crash diagnosis, 2026-10-25

SuperCollider 3.14.1 aborts on a malformed incoming OSC packet with `Bad OSC message size`. Brahma's sandbox startup self-test sent the raw byte `x` to its configured engine port. That probe could kill both an IDE interpreter and another running interpreter. It now sends a padded, valid, argument-free `/brahma/sandbox/probe` OSC message while retaining all seven sandbox checks. Never probe an OSC port with raw UDP text.

A disposable interpreter reproduced the raw-packet abort. The corrected sandbox self-test passed 7/7 and the interpreter exited normally; the restarted IDE interpreter also remained active after the corrected probe. FluCoMa's actual server plugin reported `1.0.10+sha.c1ca9ec.core.sha.f1551f70` and processed an audio buffer successfully.

Earlier native IDE crashes in Qt/Cocoa cleanup were not reproduced by the normal quit/relaunch test. This patch addresses the demonstrated OSC crash trigger, not every possible Qt failure. Preserve any future crash report rather than deleting preferences, sessions, or extensions.
