/*
  Phase 4: PHILOSOPHERS_PRISM — EQ FX
  4-band Parametric, 8-band Graphic, Shelf, Tilt, Dynamic EQ
*/

(
// ==========================================
// 4-BAND PARAMETRIC EQ
// ==========================================
SynthDef(\prism_parametric, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     // Band 1 (low shelf or peak)
     b1Freq=100, b1Gain=0, b1Q=1, b1Type=0,
     // Band 2
     b2Freq=500, b2Gain=0, b2Q=1, b2Type=1,
     // Band 3
     b3Freq=2000, b3Gain=0, b3Q=1, b3Type=1,
     // Band 4 (high shelf or peak)
     b4Freq=8000, b4Gain=0, b4Q=1, b4Type=0|

    var input, sig;

    input = In.ar(inBus, 1);

    // Band 1
    sig = Select.ar(b1Type.clip(0, 1), [
        BLowShelf.ar(input, b1Freq.clip(20, 2000), 1, b1Gain.clip(-24, 24)),
        BPeakEQ.ar(input, b1Freq.clip(20, 20000), b1Q.clip(0.1, 20).reciprocal, b1Gain.clip(-24, 24))
    ]);

    // Band 2
    sig = BPeakEQ.ar(sig, b2Freq.clip(20, 20000), b2Q.clip(0.1, 20).reciprocal, b2Gain.clip(-24, 24));

    // Band 3
    sig = BPeakEQ.ar(sig, b3Freq.clip(20, 20000), b3Q.clip(0.1, 20).reciprocal, b3Gain.clip(-24, 24));

    // Band 4
    sig = Select.ar(b4Type.clip(0, 1), [
        BHiShelf.ar(sig, b4Freq.clip(500, 20000), 1, b4Gain.clip(-24, 24)),
        BPeakEQ.ar(sig, b4Freq.clip(20, 20000), b4Q.clip(0.1, 20).reciprocal, b4Gain.clip(-24, 24))
    ]);

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// 8-BAND GRAPHIC EQ
// ==========================================
SynthDef(\prism_graphic, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     g63=0, g125=0, g250=0, g500=0,
     g1k=0, g2k=0, g4k=0, g8k=0|

    var input, sig;

    input = In.ar(inBus, 1);

    sig = BPeakEQ.ar(input, 63, 1.4.reciprocal, g63.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 125, 1.4.reciprocal, g125.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 250, 1.4.reciprocal, g250.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 500, 1.4.reciprocal, g500.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 1000, 1.4.reciprocal, g1k.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 2000, 1.4.reciprocal, g2k.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 4000, 1.4.reciprocal, g4k.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 8000, 1.4.reciprocal, g8k.clip(-12, 12));

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// HIGH/LOW SHELF
// ==========================================
SynthDef(\prism_shelf, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     lowFreq=200, lowGain=0, highFreq=4000, highGain=0|

    var input, sig;

    input = In.ar(inBus, 1);
    sig = BLowShelf.ar(input, lowFreq.clip(20, 2000), 1, lowGain.clip(-24, 24));
    sig = BHiShelf.ar(sig, highFreq.clip(500, 20000), 1, highGain.clip(-24, 24));

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// TILT EQ (Single Knob Tone Control)
// ==========================================
SynthDef(\prism_tilt, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     tilt=0, centerFreq=1000|  // -1 = dark, 0 = flat, +1 = bright

    var input, sig, tiltDb;

    input = In.ar(inBus, 1);
    tiltDb = tilt.clip(-1, 1) * 6;

    sig = BLowShelf.ar(input, centerFreq.clip(100, 5000), 1, tiltDb.neg);
    sig = BHiShelf.ar(sig, centerFreq.clip(100, 5000), 1, tiltDb);

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// DYNAMIC EQ (Frequency-Dependent Compression)
// ==========================================
SynthDef(\prism_dynamic, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     freq=2000, q=2, threshold=(-12), ratio=3,
     attack=0.005, release=0.05|

    var input, band, env, gain, sig;

    input = In.ar(inBus, 1);

    // Extract band
    band = BPF.ar(input, freq.clip(20, 20000), q.clip(0.1, 20).reciprocal);

    // Compress just that band
    env = Amplitude.kr(band, attack, release);
    gain = Select.kr((env.ampdb > threshold).asInteger, [
        1,
        (threshold.dbamp / env).pow(1 - (1 / ratio.clip(1, 20)))
    ]);

    // Apply gain reduction to the band, recombine
    sig = input - band + (band * gain);

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: PHILOSOPHERS_PRISM EQ FX Online (5 processors) ---".postln;

// ==========================================
// PATCH BAY REGISTRATION — EQ FX
// ==========================================
[
    [\prism_parametric, [
        [\b1Freq, "Band 1 frequency"], [\b1Gain, "Band 1 gain"],
        [\b2Freq, "Band 2 frequency"], [\b2Gain, "Band 2 gain"],
        [\b3Freq, "Band 3 frequency"], [\b3Gain, "Band 3 gain"],
        [\b4Freq, "Band 4 frequency"], [\b4Gain, "Band 4 gain"],
        [\mix, "Dry/wet mix"]
    ]],
    [\prism_graphic, [
        [\g63, "63Hz gain"], [\g125, "125Hz gain"],
        [\g250, "250Hz gain"], [\g500, "500Hz gain"],
        [\g1k, "1kHz gain"], [\g2k, "2kHz gain"],
        [\g4k, "4kHz gain"], [\g8k, "8kHz gain"],
        [\mix, "Dry/wet mix"]
    ]],
    [\prism_shelf, [
        [\lowFreq, "Low shelf freq"], [\lowGain, "Low shelf gain"],
        [\highFreq, "High shelf freq"], [\highGain, "High shelf gain"],
        [\mix, "Dry/wet mix"]
    ]],
    [\prism_tilt, [
        [\tilt, "Tilt amount"], [\centerFreq, "Center frequency"],
        [\mix, "Dry/wet mix"]
    ]],
    [\prism_dynamic, [
        [\freq, "Target frequency"], [\threshold, "Threshold"],
        [\ratio, "Compression ratio"], [\mix, "Dry/wet mix"]
    ]]
].do({ |moduleSpec|
    var synthName = moduleSpec[0];
    var params = moduleSpec[1];
    params.do({ |p|
        ~PATCH_BAY.registerDestination(
            (synthName.asString ++ "_" ++ p[0].asString).asSymbol,
            p[0], synthName.asString ++ " " ++ p[1]
        );
    });
});

// --- MODULE REGISTRY REGISTRATION ---
if(~MODULE_REGISTRY.notNil) {
    ~MODULE_REGISTRY.register(\prism_parametric, \fx, \prism_parametric, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \b1Freq, \default: 100, \min: 20, \max: 20000, \units: "Hz", \desc: "Band 1 frequency"),
        (\name: \b1Gain, \default: 0, \min: -24, \max: 24, \units: "dB", \desc: "Band 1 gain"),
        (\name: \b1Q, \default: 1, \min: 0.1, \max: 20, \units: "Q", \desc: "Band 1 Q factor"),
        (\name: \b1Type, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Band 1 type (0=shelf, 1=peak)"),
        (\name: \b2Freq, \default: 500, \min: 20, \max: 20000, \units: "Hz", \desc: "Band 2 frequency"),
        (\name: \b2Gain, \default: 0, \min: -24, \max: 24, \units: "dB", \desc: "Band 2 gain"),
        (\name: \b2Q, \default: 1, \min: 0.1, \max: 20, \units: "Q", \desc: "Band 2 Q factor"),
        (\name: \b2Type, \default: 1, \min: 0, \max: 1, \units: "", \desc: "Band 2 type (0=shelf, 1=peak)"),
        (\name: \b3Freq, \default: 2000, \min: 20, \max: 20000, \units: "Hz", \desc: "Band 3 frequency"),
        (\name: \b3Gain, \default: 0, \min: -24, \max: 24, \units: "dB", \desc: "Band 3 gain"),
        (\name: \b3Q, \default: 1, \min: 0.1, \max: 20, \units: "Q", \desc: "Band 3 Q factor"),
        (\name: \b3Type, \default: 1, \min: 0, \max: 1, \units: "", \desc: "Band 3 type (0=shelf, 1=peak)"),
        (\name: \b4Freq, \default: 8000, \min: 20, \max: 20000, \units: "Hz", \desc: "Band 4 frequency"),
        (\name: \b4Gain, \default: 0, \min: -24, \max: 24, \units: "dB", \desc: "Band 4 gain"),
        (\name: \b4Q, \default: 1, \min: 0.1, \max: 20, \units: "Q", \desc: "Band 4 Q factor"),
        (\name: \b4Type, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Band 4 type (0=shelf, 1=peak)"),
    ], ~SC_GRP[\rr], "4-band parametric EQ with shelf/peak modes");

    ~MODULE_REGISTRY.register(\prism_graphic, \fx, \prism_graphic, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \g63, \default: 0, \min: -12, \max: 12, \units: "dB", \desc: "63 Hz band gain"),
        (\name: \g125, \default: 0, \min: -12, \max: 12, \units: "dB", \desc: "125 Hz band gain"),
        (\name: \g250, \default: 0, \min: -12, \max: 12, \units: "dB", \desc: "250 Hz band gain"),
        (\name: \g500, \default: 0, \min: -12, \max: 12, \units: "dB", \desc: "500 Hz band gain"),
        (\name: \g1k, \default: 0, \min: -12, \max: 12, \units: "dB", \desc: "1 kHz band gain"),
        (\name: \g2k, \default: 0, \min: -12, \max: 12, \units: "dB", \desc: "2 kHz band gain"),
        (\name: \g4k, \default: 0, \min: -12, \max: 12, \units: "dB", \desc: "4 kHz band gain"),
        (\name: \g8k, \default: 0, \min: -12, \max: 12, \units: "dB", \desc: "8 kHz band gain"),
    ], ~SC_GRP[\rr], "8-band graphic EQ");

    ~MODULE_REGISTRY.register(\prism_shelf, \fx, \prism_shelf, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \lowFreq, \default: 200, \min: 20, \max: 2000, \units: "Hz", \desc: "Low shelf frequency"),
        (\name: \lowGain, \default: 0, \min: -24, \max: 24, \units: "dB", \desc: "Low shelf gain"),
        (\name: \highFreq, \default: 4000, \min: 500, \max: 20000, \units: "Hz", \desc: "High shelf frequency"),
        (\name: \highGain, \default: 0, \min: -24, \max: 24, \units: "dB", \desc: "High shelf gain"),
    ], ~SC_GRP[\rr], "High/low shelf EQ");

    ~MODULE_REGISTRY.register(\prism_tilt, \fx, \prism_tilt, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \tilt, \default: 0, \min: -1, \max: 1, \units: "", \desc: "Tilt amount (-1=dark, 0=flat, +1=bright)"),
        (\name: \centerFreq, \default: 1000, \min: 100, \max: 5000, \units: "Hz", \desc: "Tilt center frequency"),
    ], ~SC_GRP[\rr], "Single-knob tilt tone control");

    ~MODULE_REGISTRY.register(\prism_dynamic, \fx, \prism_dynamic, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \freq, \default: 2000, \min: 20, \max: 20000, \units: "Hz", \desc: "Target frequency"),
        (\name: \q, \default: 2, \min: 0.1, \max: 20, \units: "Q", \desc: "Band Q factor"),
        (\name: \threshold, \default: -12, \min: -60, \max: 0, \units: "dB", \desc: "Compression threshold"),
        (\name: \ratio, \default: 3, \min: 1, \max: 20, \units: ":1", \desc: "Compression ratio"),
        (\name: \attack, \default: 0.005, \min: 0.0001, \max: 0.5, \units: "s", \desc: "Attack time"),
        (\name: \release, \default: 0.05, \min: 0.001, \max: 1, \units: "s", \desc: "Release time"),
    ], ~SC_GRP[\rr], "Frequency-dependent dynamic EQ");

    "  -> 5 EQ FX registered with Module Registry".postln;
};
)
