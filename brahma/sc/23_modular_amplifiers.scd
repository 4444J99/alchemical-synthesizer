/*
  Phase 23: ANIMA (Life Force) — Modular Amplifiers
  VCA, Low-Pass Gate, Mixer, Crossfader, Ring Modulator

  Standard modular building blocks for amplitude control and signal routing.
  All SynthDefs follow Brahma standard interface with bus-based I/O.

  Modules:
    1. ANIMA_VCA       — Voltage Controlled Amplifier (linear/exponential)
    2. ANIMA_LPG       — Low-Pass Gate (vactrol-modeled VCA+VCF)
    3. ANIMA_MIXER     — 4-channel mixer with level and pan per channel
    4. ANIMA_CROSSFADER — A/B crossfader with CV control
    5. ANIMA_RING_MOD  — Ring modulator with dry/wet mix
*/

(
// ==========================================
// 1. ANIMA_VCA — Voltage Controlled Amplifier
// ==========================================
// Linear mode (0): direct CV-to-amplitude mapping, transparent gain staging.
// Exponential mode (1): CV shaped through squared curve, provides more
// natural musical dynamics with greater attenuation in low CV ranges.
SynthDef(\anima_vca, {
    |inBus=0, outBus=0, cvBus=0, gain=1.0, mode=0|

    var input, cv, amp, sig;

    input = In.ar(inBus, 1);
    cv = In.kr(cvBus, 1).clip(0, 1);
    gain = gain.clip(0, 2);
    mode = mode.clip(0, 1);

    // Linear: direct scaling; Exponential: squared curve for musical response
    amp = Select.kr(mode.round, [
        cv * gain,           // 0: linear
        (cv.squared) * gain  // 1: exponential
    ]);

    sig = input * amp;

    Out.ar(outBus, sig);
}).add;

// ==========================================
// 2. ANIMA_LPG — Low-Pass Gate (Vactrol Model)
// ==========================================
// Models the Buchla-style vactrol low-pass gate: a photoresistor coupled
// to an LED creates frequency-dependent amplitude control. The strike input
// triggers the vactrol circuit with per-instance random decay (Rand) to
// simulate analog component variance. Attack is fixed at ~5ms; decay ranges
// 50-500ms based on the damp parameter.
SynthDef(\anima_lpg, {
    |inBus=0, outBus=0, cvBus=0, strike=0, damp=0.5|

    var input, cv, trig, vactrolDecay, vactrolEnv;
    var cutoff, sig;

    input = In.ar(inBus, 1);
    cv = In.kr(cvBus, 1).clip(0, 1);
    strike = strike.clip(0, 1);
    damp = damp.clip(0, 1);

    // Per-instance random decay: vactrol component variance (50-500ms)
    vactrolDecay = Rand(0.05, 0.5) * damp.linlin(0, 1, 0.5, 2.0);

    // Trigger detection: strike as gate with vactrol-style envelope
    trig = Trig1.kr(strike, 0.001);

    // Vactrol envelope: ~5ms attack, variable decay
    vactrolEnv = EnvGen.kr(
        Env.perc(0.005, vactrolDecay.clip(0.05, 0.5), 1.0, -4),
        trig
    );

    // Combine strike envelope with CV input (whichever is higher drives the gate)
    vactrolEnv = max(vactrolEnv, cv);

    // Vactrol simultaneously controls both amplitude and filter cutoff
    // Cutoff range: 200 Hz (fully closed) to 12000 Hz (fully open)
    cutoff = vactrolEnv.linexp(0, 1, 200, 12000);
    sig = LPF.ar(input, cutoff.clip(20, 20000));
    sig = sig * vactrolEnv;

    Out.ar(outBus, sig);
}).add;

// ==========================================
// 3. ANIMA_MIXER — 4-Channel Mixer
// ==========================================
// Simple utility mixer: four mono inputs with independent level and pan.
// Output is stereo. Levels are clipped to safe range; pan uses standard
// -1 (left) to +1 (right) convention.
SynthDef(\anima_mixer, {
    |inBus1=0, inBus2=1, inBus3=2, inBus4=3, outBus=0,
     level1=1.0, level2=1.0, level3=1.0, level4=1.0,
     pan1=0, pan2=0, pan3=0, pan4=0|

    var ch1, ch2, ch3, ch4, mix;

    ch1 = Pan2.ar(In.ar(inBus1, 1) * level1.clip(0, 2), pan1.clip(-1, 1));
    ch2 = Pan2.ar(In.ar(inBus2, 1) * level2.clip(0, 2), pan2.clip(-1, 1));
    ch3 = Pan2.ar(In.ar(inBus3, 1) * level3.clip(0, 2), pan3.clip(-1, 1));
    ch4 = Pan2.ar(In.ar(inBus4, 1) * level4.clip(0, 2), pan4.clip(-1, 1));

    mix = ch1 + ch2 + ch3 + ch4;

    Out.ar(outBus, mix);
}).add;

// ==========================================
// 4. ANIMA_CROSSFADER — A/B Crossfader with CV
// ==========================================
// Equal-power crossfade between two audio inputs. The crossfade position
// can be set manually and modulated via CV bus. At 0 only input A is heard;
// at 1 only input B is heard; intermediate values blend both.
SynthDef(\anima_crossfader, {
    |inBusA=0, inBusB=1, outBus=0, crossfade=0.5, cvBus=0|

    var a, b, cv, xf, sig;

    a = In.ar(inBusA, 1);
    b = In.ar(inBusB, 1);
    cv = In.kr(cvBus, 1);

    xf = (crossfade + cv).clip(0, 1);

    // XFade2 expects bipolar control: -1 = full A, +1 = full B
    sig = XFade2.ar(a, b, xf * 2 - 1);

    Out.ar(outBus, sig);
}).add;

// ==========================================
// 5. ANIMA_RING_MOD — Ring Modulator
// ==========================================
// Classic ring modulation: multiplies two audio signals together,
// producing sum and difference frequencies. The mix parameter blends
// between the dry input A and the ring-modulated output.
SynthDef(\anima_ring_mod, {
    |inBusA=0, inBusB=1, outBus=0, mix=0.5|

    var a, b, ring, sig;

    a = In.ar(inBusA, 1);
    b = In.ar(inBusB, 1);
    mix = mix.clip(0, 1);

    ring = a * b;

    // Blend between dry signal A and ring-modulated output
    sig = XFade2.ar(a, ring, mix * 2 - 1);

    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: ANIMA Modular Amplifiers Online (5 modules) ---".postln;
"  ANIMA_VCA | ANIMA_LPG | ANIMA_MIXER | ANIMA_CROSSFADER | ANIMA_RING_MOD".postln;
)
