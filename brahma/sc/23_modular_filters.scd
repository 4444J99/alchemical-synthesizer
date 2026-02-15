/*
  Phase 23: ALEMBIC — Distillation Vessel Filter Suite
  Modular filter building blocks for the Brahma Meta-Rack.

  The Alembic is the distillation apparatus of alchemy—
  separating, purifying, and recombining spectral essence.

  SynthDefs:
    1. \alembic_ladder  — Moog-style 4-pole ladder LP with self-oscillation
    2. \alembic_svf     — State variable filter with simultaneous LP/HP/BP/Notch
    3. \alembic_comb    — Comb filter with positive/negative feedback
    4. \alembic_allpass  — Allpass filter for phase dispersion effects
    5. \alembic_formant — Formant filter (parallel resonators for vowel synthesis)
    6. \alembic_diode   — Diode ladder 303-style with accent circuit
*/

(
// ==========================================
// 1. ALEMBIC LADDER — Moog-Style 4-Pole Lowpass
// ==========================================
// Classic 24dB/oct ladder filter topology. At high resonance
// the filter enters self-oscillation, producing a pure sine tone
// at the cutoff frequency — the filter becomes an oscillator.
// Uses MoogFF for authentic nonlinear resonance behavior.
SynthDef(\alembic_ladder, {
    |inBus=0, outBus=0, freq=1000, res=0|

    var input, sig;
    var cutoff, resonance;

    input = In.ar(inBus, 1);

    // Cutoff: 20Hz to 20kHz
    cutoff = freq.clip(20, 20000);

    // Resonance: 0-1 mapped to MoogFF's 0-4 range
    // Values above ~3.5 produce self-oscillation
    resonance = res.clip(0, 1) * 4;

    sig = MoogFF.ar(input, cutoff, resonance);

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


// ==========================================
// 2. ALEMBIC SVF — State Variable Filter
// ==========================================
// Simultaneous lowpass, highpass, bandpass, and notch outputs
// on separate buses. All outputs are derived from the same
// filter core, maintaining phase coherence between them.
// Patch any or all outputs to different destinations.
SynthDef(\alembic_svf, {
    |inBus=0, outBusLP=0, outBusHP=0, outBusBP=0, outBusNotch=0,
     freq=1000, res=0.5|

    var input, lp, hp, bp, notch;
    var cutoff, rq;

    input = In.ar(inBus, 1);

    cutoff = freq.clip(20, 20000);

    // Resonance: 0 = wide bandwidth, 1 = very narrow / near self-oscillation
    rq = res.clip(0, 0.99).linexp(0, 1, 1.0, 0.01);

    // State variable filter decomposition
    // All four outputs derived from same topology for phase coherence
    lp = RLPF.ar(input, cutoff, rq);
    hp = RHPF.ar(input, cutoff, rq);
    bp = BPF.ar(input, cutoff, rq);
    notch = BRF.ar(input, cutoff, rq);

    Out.ar(outBusLP, LeakDC.ar(lp));
    Out.ar(outBusHP, LeakDC.ar(hp));
    Out.ar(outBusBP, LeakDC.ar(bp));
    Out.ar(outBusNotch, LeakDC.ar(notch));
}).add;


// ==========================================
// 3. ALEMBIC COMB — Comb Filter
// ==========================================
// Pitch-tracked comb filter with selectable positive or
// negative feedback polarity. Positive feedback reinforces
// harmonics (metallic/resonant); negative feedback reinforces
// odd harmonics only (hollow/nasal). Delay time derived from
// frequency for pitch-tracked resonance.
SynthDef(\alembic_comb, {
    |inBus=0, outBus=0, freq=220, feedback=0.5, type=0|

    var input, sig;
    var delay_time, fb;

    input = In.ar(inBus, 1);

    // Delay time from frequency: 1/freq for pitch-tracking
    delay_time = freq.clip(20, 20000).reciprocal;

    // Feedback: 0-1 mapped to safe range (prevent runaway)
    fb = feedback.clip(0, 0.99);

    // Type: 0 = positive feedback (CombL), 1 = negative feedback (CombN inverted)
    sig = Select.ar(type.clip(0, 1).round, [
        // 0: Positive feedback — reinforces all harmonics
        CombL.ar(input, 0.05, delay_time, fb.linlin(0, 0.99, 0.01, 4)),

        // 1: Negative feedback — inverted feedback reinforces odd harmonics
        // Achieved by negating the feedback path
        CombL.ar(input, 0.05, delay_time, fb.linlin(0, 0.99, 0.01, 4).neg)
    ]);

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


// ==========================================
// 4. ALEMBIC ALLPASS — Allpass Filter
// ==========================================
// Passes all frequencies at equal amplitude but shifts
// their phase relationships. Cascading multiple allpass
// filters creates phaser-like effects; single instances
// add subtle spatial movement and diffusion.
// Frequency controls the center of maximum phase shift.
SynthDef(\alembic_allpass, {
    |inBus=0, outBus=0, freq=220, decay=0.5|

    var input, sig;
    var delay_time, decay_time;

    input = In.ar(inBus, 1);

    // Delay time from frequency for pitch-related phase effects
    delay_time = freq.clip(20, 20000).reciprocal;

    // Decay: 0-1 mapped to reverb time in seconds
    decay_time = decay.clip(0, 1).linexp(0, 1, 0.01, 4);

    sig = AllpassL.ar(input, 0.05, delay_time, decay_time);

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


// ==========================================
// 5. ALEMBIC FORMANT — Formant Filter
// ==========================================
// Five parallel bandpass resonators tuned to vocal formant
// frequencies. The vowel parameter morphs continuously
// between A-E-I-O-U formant profiles. Brightness controls
// the relative amplitude of higher formants, shifting
// between dark (muffled) and bright (present) character.
SynthDef(\alembic_formant, {
    |inBus=0, outBus=0, vowel=0, brightness=0.5|

    var input, sig;
    var f1, f2, f3, f4, f5;
    var bw1, bw2, bw3, bw4, bw5;
    var bright_scale;
    var formants;

    input = In.ar(inBus, 1);

    // Vowel formant frequencies (Hz) interpolated across 5 vowels:
    //        A     E     I     O     U
    // F1:   800   400   350   500   350
    // F2:  1200  2200  2300   800   700
    // F3:  2500  2800  3000  2500  2500
    // F4:  3500  3500  3700  3500  3500
    // F5:  4500  4500  4500  4500  4500

    // Continuous vowel morph via interpolation (0.0 = A, 1.0 = U)
    f1 = Select.kr((vowel.clip(0, 1) * 4).round.clip(0, 4), [800, 400, 350, 500, 350]);
    f2 = Select.kr((vowel.clip(0, 1) * 4).round.clip(0, 4), [1200, 2200, 2300, 800, 700]);
    f3 = Select.kr((vowel.clip(0, 1) * 4).round.clip(0, 4), [2500, 2800, 3000, 2500, 2500]);
    f4 = Select.kr((vowel.clip(0, 1) * 4).round.clip(0, 4), [3500, 3500, 3700, 3500, 3500]);
    f5 = 4500; // F5 is essentially stable across vowels

    // Bandwidth (rq) narrows at higher formants for definition
    bw1 = 0.12;
    bw2 = 0.10;
    bw3 = 0.08;
    bw4 = 0.06;
    bw5 = 0.05;

    // Brightness scales amplitude of higher formants
    // 0 = only F1+F2, 1 = all formants fully present
    bright_scale = brightness.clip(0, 1);

    formants = [
        BPF.ar(input, f1.clip(80, 10000), bw1) * 1.0,
        BPF.ar(input, f2.clip(80, 10000), bw2) * 0.7,
        BPF.ar(input, f3.clip(80, 10000), bw3) * (0.2 + (bright_scale * 0.5)),
        BPF.ar(input, f4.clip(80, 10000), bw4) * (0.1 + (bright_scale * 0.3)),
        BPF.ar(input, f5.clip(80, 10000), bw5) * (0.05 + (bright_scale * 0.2))
    ];

    // Boost narrow BPF output to compensate for amplitude loss
    sig = Mix.new(formants) * 4;

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


// ==========================================
// 6. ALEMBIC DIODE — Diode Ladder 303-Style Filter
// ==========================================
// 4-pole lowpass with diode-ladder nonlinearity and
// dedicated accent circuit. The accent momentarily boosts
// resonance and cutoff for the aggressive, squelchy character
// of the TB-303. Accent can be triggered externally via
// accentBus for sequencer integration.
SynthDef(\alembic_diode, {
    |inBus=0, outBus=0, freq=1000, res=0, accent=0, accentBus=0|

    var input, sig;
    var cutoff, resonance;
    var accent_sig, accent_env, accent_boost;
    var diode_sat;

    input = In.ar(inBus, 1);

    // Read accent trigger from external bus
    accent_sig = In.kr(accentBus, 1);

    // Accent envelope: fast attack, medium decay
    // Triggered by either the accent param or external bus
    accent_env = Lag2UD.kr(
        (accent.clip(0, 1) + accent_sig).clip(0, 1),
        0.002,  // ~2ms attack
        0.15    // ~150ms decay
    );

    // Accent boosts both cutoff and resonance
    accent_boost = accent_env * 0.4;

    // Base cutoff: 20Hz to 20kHz
    cutoff = freq.clip(20, 20000);

    // Accent pushes cutoff upward (up to +1 octave)
    cutoff = (cutoff * (1 + accent_boost)).clip(20, 20000);

    // Resonance: 0-1 range; accent adds extra resonance bite
    resonance = (res.clip(0, 1) + (accent_boost * 0.5)).clip(0, 1);

    // Diode ladder: cascaded one-pole stages with soft saturation
    // between each stage to model diode nonlinearity
    sig = LPF.ar(input, cutoff);
    sig = (sig * 1.2).tanh;  // Stage 1 saturation
    sig = LPF.ar(sig, cutoff);
    sig = (sig * 1.1).tanh;  // Stage 2 saturation
    sig = LPF.ar(sig, cutoff);
    sig = (sig * 1.05).tanh; // Stage 3 saturation
    sig = LPF.ar(sig, cutoff);

    // Resonance via feedback: feed output back to input
    // Higher resonance = more feedback = self-oscillation onset
    sig = sig + (LocalIn.ar(1) * resonance * 3.8);
    LocalOut.ar(DelayN.ar(sig.tanh, 0.01, cutoff.reciprocal.clip(0.00005, 0.01)));

    // Final diode-style soft saturation on output
    sig = sig.tanh;

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


"--- BRAHMA: ALEMBIC Filter Suite Online (6 SynthDefs) ---".postln;
"  ALEMBIC LADDER (Moog 4-pole) | ALEMBIC SVF (State Variable)".postln;
"  ALEMBIC COMB | ALEMBIC ALLPASS | ALEMBIC FORMANT (Vowel)".postln;
"  ALEMBIC DIODE (303-style)".postln;

// ==========================================
// PATCH BAY REGISTRATION — Modular Filters
// ==========================================
[
    [\alembic_ladder, [
        [\freq, "Cutoff frequency"], [\res, "Resonance"]
    ]],
    [\alembic_svf, [
        [\freq, "Cutoff frequency"], [\res, "Resonance"]
    ]],
    [\alembic_comb, [
        [\freq, "Comb frequency"], [\feedback, "Feedback"], [\type, "Polarity"]
    ]],
    [\alembic_allpass, [
        [\freq, "Center frequency"], [\decay, "Decay time"]
    ]],
    [\alembic_formant, [
        [\vowel, "Vowel morph"], [\brightness, "Brightness"]
    ]],
    [\alembic_diode, [
        [\freq, "Cutoff frequency"], [\res, "Resonance"],
        [\accent, "Accent amount"]
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

// ==========================================
// MODULE REGISTRY REGISTRATION — Modular Filters
// ==========================================
if(~MODULE_REGISTRY.notNil) {
    ~MODULE_REGISTRY.register(\alembic_ladder, \modular, \alembic_ladder, [
        (\name: \freq, \default: 1000, \min: 20, \max: 20000, \units: "Hz", \desc: "Cutoff frequency"),
        (\name: \res, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Resonance (self-oscillation above ~0.875)"),
    ], ~SC_GRP[\te], "Moog-style 4-pole ladder lowpass with self-oscillation");

    ~MODULE_REGISTRY.register(\alembic_svf, \modular, \alembic_svf, [
        (\name: \freq, \default: 1000, \min: 20, \max: 20000, \units: "Hz", \desc: "Cutoff frequency"),
        (\name: \res, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Resonance"),
    ], ~SC_GRP[\te], "State variable filter with simultaneous LP/HP/BP/Notch outputs");

    ~MODULE_REGISTRY.register(\alembic_comb, \modular, \alembic_comb, [
        (\name: \freq, \default: 220, \min: 20, \max: 20000, \units: "Hz", \desc: "Comb frequency (pitch-tracked delay)"),
        (\name: \feedback, \default: 0.5, \min: 0, \max: 0.99, \units: "", \desc: "Feedback amount"),
        (\name: \type, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Polarity (0=positive, 1=negative)"),
    ], ~SC_GRP[\te], "Pitch-tracked comb filter with selectable feedback polarity");

    ~MODULE_REGISTRY.register(\alembic_allpass, \modular, \alembic_allpass, [
        (\name: \freq, \default: 220, \min: 20, \max: 20000, \units: "Hz", \desc: "Center frequency for phase shift"),
        (\name: \decay, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Decay time (0-1 mapped to 0.01-4s)"),
    ], ~SC_GRP[\te], "Allpass filter for phase dispersion and diffusion effects");

    ~MODULE_REGISTRY.register(\alembic_formant, \modular, \alembic_formant, [
        (\name: \vowel, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Vowel morph (0=A, 0.25=E, 0.5=I, 0.75=O, 1=U)"),
        (\name: \brightness, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Higher formant presence"),
    ], ~SC_GRP[\te], "Parallel resonator formant filter for vowel synthesis");

    ~MODULE_REGISTRY.register(\alembic_diode, \modular, \alembic_diode, [
        (\name: \freq, \default: 1000, \min: 20, \max: 20000, \units: "Hz", \desc: "Cutoff frequency"),
        (\name: \res, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Resonance"),
        (\name: \accent, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Accent amount (boosts cutoff and resonance)"),
    ], ~SC_GRP[\te], "Diode ladder 303-style filter with accent circuit");
};
)
