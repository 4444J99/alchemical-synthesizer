/*
  Phase 4: SOLVE_ET_COAGULA — Spectral FX
  Vocoder, Spectral Freeze, Blur, Pitch Shift,
  Harmonizer, Spectral Filter
*/

(
SynthDef(\solve_vocoder, {
    |inBus=0, carrierBus=0, outBus=0, mix=1.0, bypass=0,
     numBands=16, shift=0|

    var modulator, carrier, bands, sig;
    modulator = In.ar(inBus, 1);
    carrier = In.ar(carrierBus, 1);

    // 16-band vocoder
    bands = 16.collect({ |i|
        var freq = (100 * (2 ** (i * 0.5))).clip(50, 16000);
        var bw = freq * 0.15;
        var modBand = BPF.ar(modulator, freq, bw / freq);
        var carBand = BPF.ar(carrier, (freq * (2 ** (shift / 12))).clip(50, 16000), bw / freq);
        var env = Amplitude.kr(modBand, 0.005, 0.05);
        carBand * env;
    });

    sig = Mix.new(bands) * 4;
    sig = XFade2.ar(modulator, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, modulator]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\solve_spectral_freeze, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     freeze=0|

    var input, chain, frozen, sig;
    input = In.ar(inBus, 1);

    chain = FFT(LocalBuf(2048), input);
    chain = PV_Freeze(chain, freeze.clip(0, 1) > 0.5);
    frozen = IFFT(chain);

    sig = XFade2.ar(input, frozen, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\solve_spectral_blur, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     blurAmount=0.5, timeConst=0.5|

    var input, chain, blurred, sig;
    input = In.ar(inBus, 1);

    chain = FFT(LocalBuf(2048), input);
    chain = PV_MagSmear(chain, (blurAmount.clip(0, 1) * 50).asInteger.max(1));
    blurred = IFFT(chain);

    sig = XFade2.ar(input, blurred, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\solve_pitch_shift, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     semitones=0, formantPreserve=0,
     windowSize=0.2, pitchDispersion=0, timeDispersion=0.01|

    var input, shifted, sig;
    input = In.ar(inBus, 1);

    shifted = PitchShift.ar(input,
        windowSize.clip(0.01, 1),
        (2 ** (semitones.clip(-24, 24) / 12)),
        pitchDispersion.clip(0, 0.1),
        timeDispersion.clip(0, 0.1)
    );

    sig = XFade2.ar(input, shifted, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\solve_harmonizer, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     interval1=7, interval2=(-5), interval3=12, interval4=0,
     voice1Level=0.5, voice2Level=0.3, voice3Level=0.2, voice4Level=0|

    var input, v1, v2, v3, v4, harmonized, sig;
    input = In.ar(inBus, 1);

    v1 = PitchShift.ar(input, 0.2, 2 ** (interval1.clip(-24, 24) / 12), 0, 0.01) * voice1Level;
    v2 = PitchShift.ar(input, 0.2, 2 ** (interval2.clip(-24, 24) / 12), 0, 0.01) * voice2Level;
    v3 = PitchShift.ar(input, 0.2, 2 ** (interval3.clip(-24, 24) / 12), 0, 0.01) * voice3Level;
    v4 = PitchShift.ar(input, 0.2, 2 ** (interval4.clip(-24, 24) / 12), 0, 0.01) * voice4Level;

    harmonized = input + v1 + v2 + v3 + v4;

    sig = XFade2.ar(input, harmonized, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\solve_spectral_filter, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     lowBin=0.0, highBin=1.0|  // 0-1 normalized (which freq bins to pass)

    var input, chain, filtered, sig;
    input = In.ar(inBus, 1);

    chain = FFT(LocalBuf(2048), input);
    // Brick-wall filter: pass only bins between low and high
    chain = PV_BrickWall(chain, highBin.clip(0, 1) * 2 - 1);
    chain = PV_BrickWall(chain, lowBin.clip(0, 1).neg * 2 + 1);
    filtered = IFFT(chain);

    sig = XFade2.ar(input, filtered, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: SOLVE_ET_COAGULA Spectral FX Online (6 processors) ---".postln;

// ==========================================
// PATCH BAY REGISTRATION — Spectral FX
// ==========================================
[
    [\solve_vocoder, [
        [\shift, "Formant shift"], [\mix, "Dry/wet mix"]
    ]],
    [\solve_spectral_freeze, [
        [\freeze, "Freeze toggle"], [\mix, "Dry/wet mix"]
    ]],
    [\solve_spectral_blur, [
        [\blurAmount, "Blur amount"], [\mix, "Dry/wet mix"]
    ]],
    [\solve_pitch_shift, [
        [\semitones, "Pitch shift semitones"],
        [\windowSize, "Window size"], [\mix, "Dry/wet mix"]
    ]],
    [\solve_harmonizer, [
        [\interval1, "Voice 1 interval"], [\interval2, "Voice 2 interval"],
        [\voice1Level, "Voice 1 level"], [\voice2Level, "Voice 2 level"],
        [\mix, "Dry/wet mix"]
    ]],
    [\solve_spectral_filter, [
        [\lowBin, "Low bin cutoff"], [\highBin, "High bin cutoff"],
        [\mix, "Dry/wet mix"]
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
    ~MODULE_REGISTRY.register(\solve_vocoder, \fx, \solve_vocoder, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \numBands, \default: 16, \min: 4, \max: 32, \units: "", \desc: "Number of vocoder bands"),
        (\name: \shift, \default: 0, \min: -24, \max: 24, \units: "st", \desc: "Formant shift in semitones"),
    ], ~SC_GRP[\rr], "16-band vocoder with formant shift");

    ~MODULE_REGISTRY.register(\solve_spectral_freeze, \fx, \solve_spectral_freeze, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \freeze, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Freeze toggle (>0.5 = frozen)"),
    ], ~SC_GRP[\rr], "FFT spectral freeze");

    ~MODULE_REGISTRY.register(\solve_spectral_blur, \fx, \solve_spectral_blur, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \blurAmount, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Spectral blur amount"),
        (\name: \timeConst, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Time constant"),
    ], ~SC_GRP[\rr], "FFT spectral blur/smear");

    ~MODULE_REGISTRY.register(\solve_pitch_shift, \fx, \solve_pitch_shift, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \semitones, \default: 0, \min: -24, \max: 24, \units: "st", \desc: "Pitch shift in semitones"),
        (\name: \formantPreserve, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Formant preservation (placeholder)"),
        (\name: \windowSize, \default: 0.2, \min: 0.01, \max: 1, \units: "s", \desc: "FFT window size"),
        (\name: \pitchDispersion, \default: 0, \min: 0, \max: 0.1, \units: "", \desc: "Pitch randomization"),
        (\name: \timeDispersion, \default: 0.01, \min: 0, \max: 0.1, \units: "s", \desc: "Time randomization"),
    ], ~SC_GRP[\rr], "Granular pitch shifter");

    ~MODULE_REGISTRY.register(\solve_harmonizer, \fx, \solve_harmonizer, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \interval1, \default: 7, \min: -24, \max: 24, \units: "st", \desc: "Voice 1 interval in semitones"),
        (\name: \interval2, \default: -5, \min: -24, \max: 24, \units: "st", \desc: "Voice 2 interval in semitones"),
        (\name: \interval3, \default: 12, \min: -24, \max: 24, \units: "st", \desc: "Voice 3 interval in semitones"),
        (\name: \interval4, \default: 0, \min: -24, \max: 24, \units: "st", \desc: "Voice 4 interval in semitones"),
        (\name: \voice1Level, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Voice 1 level"),
        (\name: \voice2Level, \default: 0.3, \min: 0, \max: 1, \units: "", \desc: "Voice 2 level"),
        (\name: \voice3Level, \default: 0.2, \min: 0, \max: 1, \units: "", \desc: "Voice 3 level"),
        (\name: \voice4Level, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Voice 4 level"),
    ], ~SC_GRP[\rr], "4-voice pitch harmonizer");

    ~MODULE_REGISTRY.register(\solve_spectral_filter, \fx, \solve_spectral_filter, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \lowBin, \default: 0.0, \min: 0, \max: 1, \units: "", \desc: "Low bin cutoff (normalized)"),
        (\name: \highBin, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "High bin cutoff (normalized)"),
    ], ~SC_GRP[\rr], "FFT brick-wall spectral filter");

    "  -> 6 Spectral FX registered with Module Registry".postln;
};
)
