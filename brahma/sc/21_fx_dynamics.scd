/*
  Phase 4: CRUCIBLE — Dynamics FX
  Compressor, Limiter, Gate, Expander, Sidechain Ducker
  All follow: |inBus, outBus, mix=0.5, bypass=0| + specific params
*/

(
// ==========================================
// COMPRESSOR
// ==========================================
SynthDef(\crucible_compressor, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     threshold=(-12), ratio=4, attack=0.01, release=0.1,
     knee=6, makeup=0,
     sidechainBus=(-1)|  // -1 = use input as sidechain

    var input, sc, env, gain, compressed, sig;

    input = In.ar(inBus, 1);
    sc = if(sidechainBus >= 0, { In.ar(sidechainBus, 1) }, { input });

    env = Amplitude.kr(sc, attack.clip(0.0001, 1), release.clip(0.001, 2));
    env = env.ampdb;

    // Soft knee compression
    gain = Select.kr((env > threshold).asInteger, [
        0, // Below threshold: no reduction
        (env - threshold) * (1 - (1 / ratio.clip(1, 100))) * -1
    ]);

    compressed = input * (gain + makeup).dbamp;
    sig = XFade2.ar(input, compressed, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// LIMITER
// ==========================================
SynthDef(\crucible_limiter, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     ceiling=(-0.3), lookahead=0.005, release=0.05|

    var input, limited, sig;

    input = In.ar(inBus, 1);
    limited = Limiter.ar(input, ceiling.dbamp.clip(0.01, 1), lookahead.clip(0.001, 0.02));

    sig = XFade2.ar(input, limited, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// NOISE GATE
// ==========================================
SynthDef(\crucible_gate, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     threshold=(-40), range=(-80), attack=0.001, hold=0.05, release=0.1,
     sidechainBus=(-1)|

    var input, sc, env, gateSignal, gated, sig;

    input = In.ar(inBus, 1);
    sc = if(sidechainBus >= 0, { In.ar(sidechainBus, 1) }, { input });

    env = Amplitude.kr(sc, attack.clip(0.0001, 0.5), release.clip(0.001, 2));

    // Gate with hold time
    gateSignal = (env.ampdb > threshold);
    gateSignal = Trig1.kr(gateSignal, hold.clip(0.001, 1)) + gateSignal;
    gateSignal = gateSignal.clip(0, 1).lag(attack, release);

    // Range: how much to attenuate when gated (0 = full mute, -80dB = nearly mute)
    gated = input * gateSignal.linlin(0, 1, range.dbamp, 1);

    sig = XFade2.ar(input, gated, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// EXPANDER
// ==========================================
SynthDef(\crucible_expander, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     threshold=(-30), ratio=2, attack=0.005, release=0.1|

    var input, env, gain, expanded, sig;

    input = In.ar(inBus, 1);
    env = Amplitude.kr(input, attack.clip(0.0001, 0.5), release.clip(0.001, 2));

    // Expand: signals below threshold are attenuated more
    gain = Select.kr((env.ampdb < threshold).asInteger, [
        0, // Above threshold: no change
        (env.ampdb - threshold) * (ratio.clip(1, 20) - 1)
    ]);

    expanded = input * gain.dbamp;
    sig = XFade2.ar(input, expanded, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// SIDECHAIN DUCKER
// ==========================================
SynthDef(\crucible_ducker, {
    |inBus=0, outBus=0, sidechainBus=0, mix=1.0, bypass=0,
     duckAmount=0.8, attack=0.005, release=0.15|

    var input, sc, env, ducked, sig;

    input = In.ar(inBus, 1);
    sc = In.ar(sidechainBus, 1);

    env = Amplitude.kr(sc, attack.clip(0.0001, 0.5), release.clip(0.001, 2));
    ducked = input * (1 - (env * duckAmount.clip(0, 1)));

    sig = XFade2.ar(input, ducked, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// MULTIBAND COMPRESSOR (3-band)
// ==========================================
SynthDef(\crucible_multiband, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     // Crossover frequencies
     lowFreq=200, highFreq=3000,
     // Low band
     lowThresh=(-12), lowRatio=3, lowAtk=0.01, lowRel=0.1, lowMakeup=0,
     // Mid band
     midThresh=(-12), midRatio=3, midAtk=0.005, midRel=0.08, midMakeup=0,
     // High band
     highThresh=(-12), highRatio=3, highAtk=0.003, highRel=0.05, highMakeup=0,
     // Band levels
     lowLevel=1, midLevel=1, highLevel=1|

    var input, low, mid, high;
    var lowEnv, midEnv, highEnv;
    var lowGain, midGain, highGain;
    var lowComp, midComp, highComp;
    var combined, sig;

    input = In.ar(inBus, 1);

    // 3-band split via Linkwitz-Riley (cascaded Butterworth)
    low = LPF.ar(LPF.ar(input, lowFreq.clip(20, 20000)), lowFreq.clip(20, 20000));
    high = HPF.ar(HPF.ar(input, highFreq.clip(20, 20000)), highFreq.clip(20, 20000));
    mid = input - low - high; // Complementary mid extraction

    // Per-band compression
    lowEnv = Amplitude.kr(low, lowAtk.clip(0.0001, 1), lowRel.clip(0.001, 2));
    lowGain = Select.kr((lowEnv.ampdb > lowThresh).asInteger, [
        0, (lowEnv.ampdb - lowThresh) * (1 - (1 / lowRatio.clip(1, 100))) * -1
    ]);
    lowComp = low * (lowGain + lowMakeup).dbamp * lowLevel;

    midEnv = Amplitude.kr(mid, midAtk.clip(0.0001, 1), midRel.clip(0.001, 2));
    midGain = Select.kr((midEnv.ampdb > midThresh).asInteger, [
        0, (midEnv.ampdb - midThresh) * (1 - (1 / midRatio.clip(1, 100))) * -1
    ]);
    midComp = mid * (midGain + midMakeup).dbamp * midLevel;

    highEnv = Amplitude.kr(high, highAtk.clip(0.0001, 1), highRel.clip(0.001, 2));
    highGain = Select.kr((highEnv.ampdb > highThresh).asInteger, [
        0, (highEnv.ampdb - highThresh) * (1 - (1 / highRatio.clip(1, 100))) * -1
    ]);
    highComp = high * (highGain + highMakeup).dbamp * highLevel;

    combined = lowComp + midComp + highComp;

    sig = XFade2.ar(input, combined, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// DE-ESSER
// ==========================================
SynthDef(\crucible_deesser, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     freq=6000,           // Center frequency of sibilance detection
     bandwidth=2000,      // Detection bandwidth
     threshold=(-20),     // Threshold in dB
     ratio=4,             // Compression ratio for sibilance band
     attack=0.001,        // Fast attack for sibilance
     release=0.03|        // Quick release

    var input, sibilance, env, gain, deessed, sig;

    input = In.ar(inBus, 1);

    // Extract sibilance band for detection
    sibilance = BPF.ar(input, freq.clip(2000, 16000),
        (bandwidth / freq).clip(0.1, 2));

    // Detect sibilance level
    env = Amplitude.kr(sibilance, attack.clip(0.0001, 0.1), release.clip(0.001, 0.5));

    // Gain reduction when sibilance exceeds threshold
    gain = Select.kr((env.ampdb > threshold).asInteger, [
        0,
        (env.ampdb - threshold) * (1 - (1 / ratio.clip(1, 20))) * -1
    ]);

    // Apply gain reduction only to the sibilance band, recombine
    deessed = input - sibilance + (sibilance * gain.dbamp);

    sig = XFade2.ar(input, deessed, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: CRUCIBLE Dynamics FX Online (7 processors) ---".postln;

// ==========================================
// PATCH BAY REGISTRATION — Dynamics FX
// ==========================================
[
    [\crucible_compressor, [
        [\threshold, "Threshold dB"], [\ratio, "Ratio"],
        [\attack, "Attack time"], [\release, "Release time"],
        [\makeup, "Makeup gain"], [\mix, "Dry/wet mix"]
    ]],
    [\crucible_limiter, [
        [\ceiling, "Ceiling dB"], [\mix, "Dry/wet mix"]
    ]],
    [\crucible_gate, [
        [\threshold, "Threshold dB"], [\range, "Gate range"],
        [\attack, "Attack"], [\hold, "Hold time"], [\release, "Release"],
        [\mix, "Dry/wet mix"]
    ]],
    [\crucible_expander, [
        [\threshold, "Threshold dB"], [\ratio, "Expansion ratio"],
        [\attack, "Attack"], [\release, "Release"], [\mix, "Dry/wet mix"]
    ]],
    [\crucible_ducker, [
        [\duckAmount, "Duck amount"], [\attack, "Attack"],
        [\release, "Release"], [\mix, "Dry/wet mix"]
    ]],
    [\crucible_multiband, [
        [\lowFreq, "Low crossover"], [\highFreq, "High crossover"],
        [\lowThresh, "Low threshold"], [\midThresh, "Mid threshold"],
        [\highThresh, "High threshold"], [\mix, "Dry/wet mix"]
    ]],
    [\crucible_deesser, [
        [\freq, "Sibilance frequency"], [\threshold, "Threshold"],
        [\ratio, "Ratio"], [\mix, "Dry/wet mix"]
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
    ~MODULE_REGISTRY.register(\crucible_compressor, \fx, \crucible_compressor, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \threshold, \default: -12, \min: -60, \max: 0, \units: "dB", \desc: "Compression threshold"),
        (\name: \ratio, \default: 4, \min: 1, \max: 100, \units: ":1", \desc: "Compression ratio"),
        (\name: \attack, \default: 0.01, \min: 0.0001, \max: 1, \units: "s", \desc: "Attack time"),
        (\name: \release, \default: 0.1, \min: 0.001, \max: 2, \units: "s", \desc: "Release time"),
        (\name: \knee, \default: 6, \min: 0, \max: 30, \units: "dB", \desc: "Soft knee width"),
        (\name: \makeup, \default: 0, \min: 0, \max: 30, \units: "dB", \desc: "Makeup gain"),
    ], ~SC_GRP[\rr], "Dynamics compressor with sidechain");

    ~MODULE_REGISTRY.register(\crucible_limiter, \fx, \crucible_limiter, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \ceiling, \default: -0.3, \min: -30, \max: 0, \units: "dB", \desc: "Ceiling level"),
        (\name: \lookahead, \default: 0.005, \min: 0.001, \max: 0.02, \units: "s", \desc: "Lookahead time"),
        (\name: \release, \default: 0.05, \min: 0.001, \max: 1, \units: "s", \desc: "Release time"),
    ], ~SC_GRP[\rr], "Brickwall limiter");

    ~MODULE_REGISTRY.register(\crucible_gate, \fx, \crucible_gate, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \threshold, \default: -40, \min: -80, \max: 0, \units: "dB", \desc: "Gate threshold"),
        (\name: \range, \default: -80, \min: -80, \max: 0, \units: "dB", \desc: "Attenuation range when gated"),
        (\name: \attack, \default: 0.001, \min: 0.0001, \max: 0.5, \units: "s", \desc: "Attack time"),
        (\name: \hold, \default: 0.05, \min: 0.001, \max: 1, \units: "s", \desc: "Hold time"),
        (\name: \release, \default: 0.1, \min: 0.001, \max: 2, \units: "s", \desc: "Release time"),
    ], ~SC_GRP[\rr], "Noise gate with sidechain and hold");

    ~MODULE_REGISTRY.register(\crucible_expander, \fx, \crucible_expander, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \threshold, \default: -30, \min: -60, \max: 0, \units: "dB", \desc: "Expansion threshold"),
        (\name: \ratio, \default: 2, \min: 1, \max: 20, \units: ":1", \desc: "Expansion ratio"),
        (\name: \attack, \default: 0.005, \min: 0.0001, \max: 0.5, \units: "s", \desc: "Attack time"),
        (\name: \release, \default: 0.1, \min: 0.001, \max: 2, \units: "s", \desc: "Release time"),
    ], ~SC_GRP[\rr], "Downward expander");

    ~MODULE_REGISTRY.register(\crucible_ducker, \fx, \crucible_ducker, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \duckAmount, \default: 0.8, \min: 0, \max: 1, \units: "", \desc: "Ducking depth"),
        (\name: \attack, \default: 0.005, \min: 0.0001, \max: 0.5, \units: "s", \desc: "Attack time"),
        (\name: \release, \default: 0.15, \min: 0.001, \max: 2, \units: "s", \desc: "Release time"),
    ], ~SC_GRP[\rr], "Sidechain ducker");

    ~MODULE_REGISTRY.register(\crucible_multiband, \fx, \crucible_multiband, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \lowFreq, \default: 200, \min: 20, \max: 20000, \units: "Hz", \desc: "Low crossover frequency"),
        (\name: \highFreq, \default: 3000, \min: 20, \max: 20000, \units: "Hz", \desc: "High crossover frequency"),
        (\name: \lowThresh, \default: -12, \min: -60, \max: 0, \units: "dB", \desc: "Low band threshold"),
        (\name: \lowRatio, \default: 3, \min: 1, \max: 100, \units: ":1", \desc: "Low band ratio"),
        (\name: \lowAtk, \default: 0.01, \min: 0.0001, \max: 1, \units: "s", \desc: "Low band attack"),
        (\name: \lowRel, \default: 0.1, \min: 0.001, \max: 2, \units: "s", \desc: "Low band release"),
        (\name: \lowMakeup, \default: 0, \min: 0, \max: 30, \units: "dB", \desc: "Low band makeup gain"),
        (\name: \midThresh, \default: -12, \min: -60, \max: 0, \units: "dB", \desc: "Mid band threshold"),
        (\name: \midRatio, \default: 3, \min: 1, \max: 100, \units: ":1", \desc: "Mid band ratio"),
        (\name: \midAtk, \default: 0.005, \min: 0.0001, \max: 1, \units: "s", \desc: "Mid band attack"),
        (\name: \midRel, \default: 0.08, \min: 0.001, \max: 2, \units: "s", \desc: "Mid band release"),
        (\name: \midMakeup, \default: 0, \min: 0, \max: 30, \units: "dB", \desc: "Mid band makeup gain"),
        (\name: \highThresh, \default: -12, \min: -60, \max: 0, \units: "dB", \desc: "High band threshold"),
        (\name: \highRatio, \default: 3, \min: 1, \max: 100, \units: ":1", \desc: "High band ratio"),
        (\name: \highAtk, \default: 0.003, \min: 0.0001, \max: 1, \units: "s", \desc: "High band attack"),
        (\name: \highRel, \default: 0.05, \min: 0.001, \max: 2, \units: "s", \desc: "High band release"),
        (\name: \highMakeup, \default: 0, \min: 0, \max: 30, \units: "dB", \desc: "High band makeup gain"),
        (\name: \lowLevel, \default: 1, \min: 0, \max: 2, \units: "", \desc: "Low band output level"),
        (\name: \midLevel, \default: 1, \min: 0, \max: 2, \units: "", \desc: "Mid band output level"),
        (\name: \highLevel, \default: 1, \min: 0, \max: 2, \units: "", \desc: "High band output level"),
    ], ~SC_GRP[\rr], "3-band multiband compressor");

    ~MODULE_REGISTRY.register(\crucible_deesser, \fx, \crucible_deesser, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \freq, \default: 6000, \min: 2000, \max: 16000, \units: "Hz", \desc: "Sibilance center frequency"),
        (\name: \bandwidth, \default: 2000, \min: 100, \max: 8000, \units: "Hz", \desc: "Detection bandwidth"),
        (\name: \threshold, \default: -20, \min: -60, \max: 0, \units: "dB", \desc: "Detection threshold"),
        (\name: \ratio, \default: 4, \min: 1, \max: 20, \units: ":1", \desc: "Compression ratio for sibilance"),
        (\name: \attack, \default: 0.001, \min: 0.0001, \max: 0.1, \units: "s", \desc: "Attack time"),
        (\name: \release, \default: 0.03, \min: 0.001, \max: 0.5, \units: "s", \desc: "Release time"),
    ], ~SC_GRP[\rr], "De-esser for sibilance reduction");

    "  -> 7 Dynamics FX registered with Module Registry".postln;
};
)
