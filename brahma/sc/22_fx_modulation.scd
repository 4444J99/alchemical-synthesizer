/*
  Phase 4: MAELSTROM — Modulation FX
  Chorus, Flanger, Phaser, Vibrato, Tremolo, Ring Mod,
  Frequency Shifter, Rotary Speaker
*/

(
SynthDef(\maelstrom_chorus, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     rate=0.5, depth=0.005, voices=3, spread=0.5|

    var input, chorus, sig;
    input = In.ar(inBus, 1);

    chorus = Mix.fill(voices.clip(1, 6), { |i|
        var lfo = SinOsc.kr(rate.clip(0.01, 10) * rrand(0.9, 1.1), rrand(0, 2pi));
        var dt = 0.02 + (lfo * depth.clip(0, 0.03));
        var pan = (i / voices.max(1) * 2 - 1) * spread.clip(0, 1);
        Pan2.ar(DelayL.ar(input, 0.05, dt), pan);
    }) / voices.max(1);

    sig = XFade2.ar(Pan2.ar(input), chorus, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\maelstrom_flanger, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     rate=0.3, depth=0.003, feedback=0.5, manual=0.003|

    var input, lfo, delayed, sig;
    input = In.ar(inBus, 1);

    lfo = SinOsc.kr(rate.clip(0.01, 10));
    delayed = DelayL.ar(
        input + (LocalIn.ar(1) * feedback.clip(-0.95, 0.95)),
        0.02,
        (manual + (lfo * depth)).clip(0.0001, 0.02)
    );
    LocalOut.ar(delayed);

    sig = XFade2.ar(input, input + delayed, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\maelstrom_phaser, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     rate=0.3, depth=0.5, stages=4, feedback=0.3, stereoPhase=0.25|

    var input, lfo, phased, sig;
    input = In.ar(inBus, 1);

    lfo = SinOsc.kr(rate.clip(0.01, 10));

    // Cascade of allpass filters
    phased = input;
    stages.clip(2, 12).do({ |i|
        var freq = (200 + (lfo * depth.clip(0, 1) * 3000) + (i * 200)).clip(50, 15000);
        phased = AllpassL.ar(phased, 0.01, freq.reciprocal.clip(0.00005, 0.01), 0.001);
    });

    phased = phased + (input * feedback.clip(-0.9, 0.9));

    sig = XFade2.ar(input, phased, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\maelstrom_vibrato, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     rate=5, depth=0.005, delay=0.01|

    var input, lfo, vibrated, sig;
    input = In.ar(inBus, 1);

    lfo = SinOsc.kr(rate.clip(0.1, 20));
    vibrated = DelayL.ar(input, 0.05, (delay + (lfo * depth)).clip(0.0001, 0.05));

    sig = XFade2.ar(input, vibrated, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\maelstrom_tremolo, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     rate=4, depth=0.8, shape=0, stereoPhase=0.25|

    var input, lfoL, lfoR, sig;
    input = In.ar(inBus, 1);

    lfoL = Select.kr(shape.clip(0, 2).round, [
        SinOsc.kr(rate.clip(0.1, 30)),
        LFTri.kr(rate.clip(0.1, 30)),
        LFPulse.kr(rate.clip(0.1, 30)).bipolar
    ]).unipolar;

    lfoR = Select.kr(shape.clip(0, 2).round, [
        SinOsc.kr(rate.clip(0.1, 30), stereoPhase * 2pi),
        LFTri.kr(rate.clip(0.1, 30), stereoPhase * 2),
        LFPulse.kr(rate.clip(0.1, 30), stereoPhase).bipolar
    ]).unipolar;

    sig = [
        input * (1 - (depth.clip(0, 1) * (1 - lfoL))),
        input * (1 - (depth.clip(0, 1) * (1 - lfoR)))
    ];

    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\maelstrom_ring_mod, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     carrierFreq=440|

    var input, ring, sig;
    input = In.ar(inBus, 1);
    ring = input * SinOsc.ar(carrierFreq.clip(1, 10000));

    sig = XFade2.ar(input, ring, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\maelstrom_freq_shift, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     shift=0, feedback=0|  // shift in Hz

    var input, shifted, sig;
    input = In.ar(inBus, 1);

    shifted = FreqShift.ar(input + (LocalIn.ar(1) * feedback.clip(0, 0.9)),
        shift.clip(-5000, 5000));
    LocalOut.ar(shifted);

    sig = XFade2.ar(input, shifted, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\maelstrom_rotary, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     speed=0,         // 0=slow, 1=fast
     acceleration=0.5|  // How quickly it transitions

    var input, slowRate, fastRate, rate, lfo, ampMod, freqMod, sig;
    input = In.ar(inBus, 1);

    slowRate = 0.8;
    fastRate = 6.5;
    rate = Lag.kr(Select.kr(speed.clip(0, 1).round, [slowRate, fastRate]),
        acceleration.clip(0.1, 5));

    // Amplitude modulation (speaker rotation)
    lfo = SinOsc.kr(rate);
    ampMod = lfo.unipolar * 0.3 + 0.7;

    // Frequency modulation (doppler)
    freqMod = lfo * 0.001;

    sig = [
        DelayL.ar(input, 0.01, 0.005 + freqMod) * ampMod,
        DelayL.ar(input, 0.01, 0.005 - freqMod) * (1 - (ampMod - 0.7))
    ];

    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);
    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: MAELSTROM Modulation FX Online (8 processors) ---".postln;

// ==========================================
// PATCH BAY REGISTRATION — Modulation FX
// ==========================================
[
    [\maelstrom_chorus, [
        [\rate, "LFO rate"], [\depth, "Modulation depth"],
        [\voices, "Voice count"], [\mix, "Dry/wet mix"]
    ]],
    [\maelstrom_flanger, [
        [\rate, "LFO rate"], [\depth, "Modulation depth"],
        [\feedback, "Feedback"], [\mix, "Dry/wet mix"]
    ]],
    [\maelstrom_phaser, [
        [\rate, "LFO rate"], [\depth, "Modulation depth"],
        [\stages, "Allpass stages"], [\feedback, "Feedback"],
        [\mix, "Dry/wet mix"]
    ]],
    [\maelstrom_vibrato, [
        [\rate, "Vibrato rate"], [\depth, "Vibrato depth"],
        [\mix, "Dry/wet mix"]
    ]],
    [\maelstrom_tremolo, [
        [\rate, "Tremolo rate"], [\depth, "Tremolo depth"],
        [\shape, "LFO shape"]
    ]],
    [\maelstrom_ring_mod, [
        [\carrierFreq, "Carrier frequency"], [\mix, "Dry/wet mix"]
    ]],
    [\maelstrom_freq_shift, [
        [\shift, "Frequency shift Hz"], [\feedback, "Feedback"],
        [\mix, "Dry/wet mix"]
    ]],
    [\maelstrom_rotary, [
        [\speed, "Rotor speed"], [\acceleration, "Speed ramp time"]
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
    ~MODULE_REGISTRY.register(\maelstrom_chorus, \fx, \maelstrom_chorus, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \rate, \default: 0.5, \min: 0.01, \max: 10, \units: "Hz", \desc: "LFO rate"),
        (\name: \depth, \default: 0.005, \min: 0, \max: 0.03, \units: "s", \desc: "Modulation depth"),
        (\name: \voices, \default: 3, \min: 1, \max: 6, \units: "", \desc: "Number of chorus voices"),
        (\name: \spread, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Stereo spread"),
    ], ~SC_GRP[\rr], "Multi-voice chorus with stereo spread");

    ~MODULE_REGISTRY.register(\maelstrom_flanger, \fx, \maelstrom_flanger, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \rate, \default: 0.3, \min: 0.01, \max: 10, \units: "Hz", \desc: "LFO rate"),
        (\name: \depth, \default: 0.003, \min: 0, \max: 0.02, \units: "s", \desc: "Modulation depth"),
        (\name: \feedback, \default: 0.5, \min: -0.95, \max: 0.95, \units: "", \desc: "Feedback amount"),
        (\name: \manual, \default: 0.003, \min: 0.0001, \max: 0.02, \units: "s", \desc: "Manual delay offset"),
    ], ~SC_GRP[\rr], "Flanger with feedback");

    ~MODULE_REGISTRY.register(\maelstrom_phaser, \fx, \maelstrom_phaser, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \rate, \default: 0.3, \min: 0.01, \max: 10, \units: "Hz", \desc: "LFO rate"),
        (\name: \depth, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Modulation depth"),
        (\name: \stages, \default: 4, \min: 2, \max: 12, \units: "", \desc: "Number of allpass stages"),
        (\name: \feedback, \default: 0.3, \min: -0.9, \max: 0.9, \units: "", \desc: "Feedback amount"),
        (\name: \stereoPhase, \default: 0.25, \min: 0, \max: 1, \units: "", \desc: "Stereo LFO phase offset"),
    ], ~SC_GRP[\rr], "Multi-stage phaser");

    ~MODULE_REGISTRY.register(\maelstrom_vibrato, \fx, \maelstrom_vibrato, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \rate, \default: 5, \min: 0.1, \max: 20, \units: "Hz", \desc: "Vibrato rate"),
        (\name: \depth, \default: 0.005, \min: 0, \max: 0.05, \units: "s", \desc: "Vibrato depth"),
        (\name: \delay, \default: 0.01, \min: 0.0001, \max: 0.05, \units: "s", \desc: "Base delay time"),
    ], ~SC_GRP[\rr], "Pitch vibrato via delay modulation");

    ~MODULE_REGISTRY.register(\maelstrom_tremolo, \fx, \maelstrom_tremolo, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \rate, \default: 4, \min: 0.1, \max: 30, \units: "Hz", \desc: "Tremolo rate"),
        (\name: \depth, \default: 0.8, \min: 0, \max: 1, \units: "", \desc: "Tremolo depth"),
        (\name: \shape, \default: 0, \min: 0, \max: 2, \units: "", \desc: "LFO shape (0=sine, 1=tri, 2=square)"),
        (\name: \stereoPhase, \default: 0.25, \min: 0, \max: 1, \units: "", \desc: "Stereo LFO phase offset"),
    ], ~SC_GRP[\rr], "Stereo tremolo with selectable shape");

    ~MODULE_REGISTRY.register(\maelstrom_ring_mod, \fx, \maelstrom_ring_mod, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \carrierFreq, \default: 440, \min: 1, \max: 10000, \units: "Hz", \desc: "Carrier frequency"),
    ], ~SC_GRP[\rr], "Ring modulator");

    ~MODULE_REGISTRY.register(\maelstrom_freq_shift, \fx, \maelstrom_freq_shift, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \shift, \default: 0, \min: -5000, \max: 5000, \units: "Hz", \desc: "Frequency shift amount"),
        (\name: \feedback, \default: 0, \min: 0, \max: 0.9, \units: "", \desc: "Feedback amount"),
    ], ~SC_GRP[\rr], "Frequency shifter with feedback");

    ~MODULE_REGISTRY.register(\maelstrom_rotary, \fx, \maelstrom_rotary, [
        (\name: \mix, \default: 1.0, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \speed, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Rotor speed (0=slow, 1=fast)"),
        (\name: \acceleration, \default: 0.5, \min: 0.1, \max: 5, \units: "s", \desc: "Speed transition time"),
    ], ~SC_GRP[\rr], "Rotary speaker simulation with doppler");

    "  -> 8 Modulation FX registered with Module Registry".postln;
};
)
