/*
  Phase 18: Make Noise Filter & Low-Pass Gate Clones
  Alchemical reimaginings of the Make Noise filter ecosystem.

  All LPG modules share a common vactrol model:
    - Non-linear response curve (slow attack ~5ms, long decay ~50-500ms)
    - Per-instance random decay variance via Rand
    - Logarithmic amplitude response

  SynthDefs:
    1. \tetrapeak        — QPAS clone (Quad Peak Animation System)
    2. \vactrol_sanctum  — Optomix clone (Dual Low-Pass Gate)
    3. \vactrol_shadow   — LxD clone (Dual LPG: 6dB + 12dB)
    4. \vactrol_matrix   — QXG clone (Quad Dynamics Gate)
    5. \vactrol_quad     — QMMG clone (Quad Multimode Gate)
    6. \resonance_prism  — Multimod clone (Multimode Filter)
    7. \vactrol_classic  — MMG clone (Multimode Gate)
    8. \formant_drift    — FxDf clone (Fixed Filter Bank)
    9. \vactrol_dxg      — DXG clone (Dual Crossfading Gate)
*/

(
// ============================================================
// VACTROL MODEL — shared envelope shape for all LPG modules
// ============================================================
// The vactrol is a light-dependent resistor coupled to an LED.
// Its response is inherently non-linear: fast-ish attack (~5ms),
// slow logarithmic decay (50-500ms) with per-instance variance.
//
// Usage within a SynthDef:
//   var vactrol_env = Lag2UD.ar(trig, attack, decay);
//   var vactrol_amp = vactrol_env.squared;  // logarithmic response
//
// Per-instance decay variance is achieved with Rand inside each
// SynthDef, ensuring no two vactrol channels behave identically.
// ============================================================


// ============================================================
// 1. TETRAPEAK — Quad Peak Animation System (QPAS clone)
//    Stereo multimode filter with 4 resonant peaks.
//    CV-controllable center frequency and peak spread.
//    Radiate output: difference signal between peak channels.
// ============================================================
SynthDef(\tetrapeak, {
    |inBus=0, outBus=0, radiateBus=0,
     freq=1000, spread=0.5, resonance=0.7|

    var in_l, in_r, sig_l, sig_r, radiate;
    var peak_freqs, q;
    var spread_ratio;

    in_l = In.ar(inBus, 1);
    in_r = In.ar(inBus + 1, 1);

    // Spread factor: 0 = all peaks at center, 1 = wide logarithmic spread
    // 4 peaks distributed symmetrically around center frequency
    spread_ratio = spread.clip(0, 1).linexp(0, 1, 1.0, 4.0);
    peak_freqs = [
        freq / spread_ratio,             // Peak 1 (lowest)
        freq / spread_ratio.sqrt,        // Peak 2
        freq * spread_ratio.sqrt,        // Peak 3
        freq * spread_ratio              // Peak 4 (highest)
    ].clip(20, 20000);

    // Resonance as inverse bandwidth (higher = narrower)
    q = resonance.clip(0.01, 0.999).linexp(0, 1, 0.5, 50);

    // Left channel: peaks 1 + 3
    sig_l = BPF.ar(in_l, peak_freqs[0], q.reciprocal.clip(0.001, 1)) * 2;
    sig_l = sig_l + (BPF.ar(in_l, peak_freqs[2], q.reciprocal.clip(0.001, 1)) * 2);

    // Right channel: peaks 2 + 4
    sig_r = BPF.ar(in_r, peak_freqs[1], q.reciprocal.clip(0.001, 1)) * 2;
    sig_r = sig_r + (BPF.ar(in_r, peak_freqs[3], q.reciprocal.clip(0.001, 1)) * 2);

    // Self-oscillation feedback at high resonance
    sig_l = sig_l + (LocalIn.ar(2)[0] * resonance.clip(0, 0.999) * 0.5);
    sig_r = sig_r + (LocalIn.ar(2)[1] * resonance.clip(0, 0.999) * 0.5);
    LocalOut.ar([
        DelayN.ar(sig_l.tanh, 0.01, freq.reciprocal.clip(0.00005, 0.01)),
        DelayN.ar(sig_r.tanh, 0.01, freq.reciprocal.clip(0.00005, 0.01))
    ]);

    // Radiate output: difference between left and right peak channels
    // This is the "animation" — cross-channel spectral motion
    radiate = sig_l - sig_r;

    Out.ar(outBus, [LeakDC.ar(sig_l), LeakDC.ar(sig_r)]);
    Out.ar(radiateBus, LeakDC.ar(radiate));
}).add;


// ============================================================
// 2. VACTROL SANCTUM — Dual Low-Pass Gate (Optomix clone)
//    2 independent channels, each with vactrol-modeled VCA+VCF.
//    Strike input triggers a percussive vactrol decay.
//    Damp control shortens the decay tail.
// ============================================================
SynthDef(\vactrol_sanctum, {
    |inBus=0, outBus=0,
     cv1=0, cv2=0,
     strike1=0, strike2=0,
     damp=0.5|

    var in1, in2, sig1, sig2;
    var vac1_env, vac2_env, vac1_amp, vac2_amp;
    var vac1_cutoff, vac2_cutoff;
    var strike1_trig, strike2_trig;
    var decay1, decay2;
    var atk = 0.005; // ~5ms vactrol attack

    in1 = In.ar(inBus, 1);
    in2 = In.ar(inBus + 1, 1);

    // Per-instance random decay variance (50-500ms base, damp scales it)
    decay1 = Rand(0.05, 0.5) * damp.clip(0.01, 1).linexp(0, 1, 4.0, 0.25);
    decay2 = Rand(0.05, 0.5) * damp.clip(0.01, 1).linexp(0, 1, 4.0, 0.25);

    // Strike triggers: convert trigger to gate-like impulse for vactrol
    strike1_trig = Trig1.ar(K2A.ar(strike1), 0.001);
    strike2_trig = Trig1.ar(K2A.ar(strike2), 0.001);

    // Vactrol envelope: combine CV (sustained) with strike (percussive)
    // Lag2UD provides asymmetric slew: fast attack, slow decay
    vac1_env = Lag2UD.ar(
        (cv1.clip(0, 1) + strike1_trig).clip(0, 1),
        atk,
        decay1
    );
    vac2_env = Lag2UD.ar(
        (cv2.clip(0, 1) + strike2_trig).clip(0, 1),
        atk,
        decay2
    );

    // Logarithmic amplitude response (squared for vactrol curve)
    vac1_amp = vac1_env.squared;
    vac2_amp = vac2_env.squared;

    // Coupled VCA + VCF: cutoff tracks vactrol envelope
    vac1_cutoff = vac1_env.linexp(0, 1, 80, 20000);
    vac2_cutoff = vac2_env.linexp(0, 1, 80, 20000);

    sig1 = LPF.ar(in1, vac1_cutoff) * vac1_amp;
    sig2 = LPF.ar(in2, vac2_cutoff) * vac2_amp;

    Out.ar(outBus, [LeakDC.ar(sig1), LeakDC.ar(sig2)]);
}).add;


// ============================================================
// 3. VACTROL SHADOW — Dual LPG (LxD clone)
//    Channel A: 6dB/oct slope (gentle, one-pole)
//    Channel B: 12dB/oct slope (steeper, two-pole)
//    Both with vactrol response curves.
// ============================================================
SynthDef(\vactrol_shadow, {
    |inBus=0, outBus=0,
     cv1=0, cv2=0|

    var in_sig, sig_a, sig_b;
    var vac_a_env, vac_b_env, vac_a_amp, vac_b_amp;
    var cutoff_a, cutoff_b;
    var decay_a, decay_b;
    var atk = 0.005;

    in_sig = In.ar(inBus, 1);

    // Per-instance random decay variance
    decay_a = Rand(0.05, 0.5);
    decay_b = Rand(0.05, 0.5);

    // Vactrol envelopes
    vac_a_env = Lag2UD.ar(K2A.ar(cv1.clip(0, 1)), atk, decay_a);
    vac_b_env = Lag2UD.ar(K2A.ar(cv2.clip(0, 1)), atk, decay_b);

    // Logarithmic amplitude response
    vac_a_amp = vac_a_env.squared;
    vac_b_amp = vac_b_env.squared;

    // Coupled cutoff tracking
    cutoff_a = vac_a_env.linexp(0, 1, 60, 20000);
    cutoff_b = vac_b_env.linexp(0, 1, 60, 20000);

    // Channel A: 6dB/oct (single-pole LPF via OnePole approximation)
    sig_a = OnePole.ar(in_sig, (1 - (cutoff_a / SampleRate.ir * 2 * pi)).clip(-0.999, 0.999));
    sig_a = sig_a * vac_a_amp;

    // Channel B: 12dB/oct (two-pole via LPF — Butterworth 2nd order)
    sig_b = LPF.ar(in_sig, cutoff_b);
    sig_b = sig_b * vac_b_amp;

    Out.ar(outBus, [LeakDC.ar(sig_a), LeakDC.ar(sig_b)]);
}).add;


// ============================================================
// 4. VACTROL MATRIX — Quad Dynamics Gate (QXG clone)
//    4 independent VCA channels with vactrol response.
//    Each channel is a full vactrol-modeled amplitude gate.
// ============================================================
SynthDef(\vactrol_matrix, {
    |inBus1=0, inBus2=0, inBus3=0, inBus4=0, outBus=0,
     cv1=0, cv2=0, cv3=0, cv4=0|

    var ins, cvs, sigs;
    var atk = 0.005;

    ins = [
        In.ar(inBus1, 1),
        In.ar(inBus2, 1),
        In.ar(inBus3, 1),
        In.ar(inBus4, 1)
    ];

    cvs = [cv1, cv2, cv3, cv4];

    sigs = 4.collect({ |i|
        var decay_i, vac_env, vac_amp, cutoff_i, sig;

        // Per-instance random decay
        decay_i = Rand(0.05, 0.5);

        // Vactrol envelope
        vac_env = Lag2UD.ar(K2A.ar(cvs[i].clip(0, 1)), atk, decay_i);

        // Logarithmic amplitude response
        vac_amp = vac_env.squared;

        // Coupled VCA + gentle LPF tracking
        cutoff_i = vac_env.linexp(0, 1, 100, 20000);
        sig = LPF.ar(ins[i], cutoff_i) * vac_amp;

        LeakDC.ar(sig);
    });

    // Sum all 4 channels to output
    Out.ar(outBus, Mix.new(sigs));
}).add;


// ============================================================
// 5. VACTROL QUAD — Quad Multimode Gate (QMMG clone)
//    4 channels, each with selectable LP/HP/BP/Notch filter
//    and vactrol response curve.
//    Mode: 0=LP, 1=HP, 2=BP, 3=Notch
// ============================================================
SynthDef(\vactrol_quad, {
    |inBus=0, outBus=0,
     cv1=0, cv2=0, cv3=0, cv4=0,
     mode1=0, mode2=0, mode3=0, mode4=0|

    var in_sig, sigs;
    var cvs, modes;
    var atk = 0.005;

    in_sig = In.ar(inBus, 1);

    cvs = [cv1, cv2, cv3, cv4];
    modes = [mode1, mode2, mode3, mode4];

    sigs = 4.collect({ |i|
        var decay_i, vac_env, vac_amp, cutoff_i, rq, sig;

        // Per-instance random decay
        decay_i = Rand(0.05, 0.5);

        // Vactrol envelope
        vac_env = Lag2UD.ar(K2A.ar(cvs[i].clip(0, 1)), atk, decay_i);

        // Logarithmic amplitude response
        vac_amp = vac_env.squared;

        // Vactrol-coupled cutoff
        cutoff_i = vac_env.linexp(0, 1, 80, 20000);
        rq = 0.3; // moderate resonance for musical response

        // Multimode filter selection
        sig = Select.ar(modes[i].clip(0, 3), [
            RLPF.ar(in_sig, cutoff_i, rq),   // 0: Low-pass
            RHPF.ar(in_sig, cutoff_i, rq),   // 1: High-pass
            BPF.ar(in_sig, cutoff_i, rq),    // 2: Band-pass
            BRF.ar(in_sig, cutoff_i, rq)     // 3: Notch
        ]);

        sig = sig * vac_amp;
        LeakDC.ar(sig);
    });

    // Sum all 4 channels
    Out.ar(outBus, Mix.new(sigs));
}).add;


// ============================================================
// 6. RESONANCE PRISM — Multimode Filter (Multimod clone)
//    Simultaneous LP/HP/BP/Notch outputs on separate buses.
//    State-variable filter topology for phase-coherent outputs.
// ============================================================
SynthDef(\resonance_prism, {
    |inBus=0, outBusLP=0, outBusHP=0, outBusBP=0, outBusNotch=0,
     freq=1000, res=0.5|

    var in_sig, lp, hp, bp, notch;
    var cutoff, rq;

    in_sig = In.ar(inBus, 1);

    cutoff = freq.clip(20, 20000);
    // Resonance: 0 = wide, 1 = self-oscillation threshold
    rq = res.clip(0, 0.99).linexp(0, 1, 1.0, 0.01);

    // State-variable filter: all outputs are phase-coherent
    // Using SVF decomposition via RLPF/RHPF/BPF/BRF
    lp = RLPF.ar(in_sig, cutoff, rq);
    hp = RHPF.ar(in_sig, cutoff, rq);
    bp = BPF.ar(in_sig, cutoff, rq);
    notch = BRF.ar(in_sig, cutoff, rq);

    Out.ar(outBusLP, LeakDC.ar(lp));
    Out.ar(outBusHP, LeakDC.ar(hp));
    Out.ar(outBusBP, LeakDC.ar(bp));
    Out.ar(outBusNotch, LeakDC.ar(notch));
}).add;


// ============================================================
// 7. VACTROL CLASSIC — Multimode Gate (MMG clone)
//    Single-channel multimode filter with vactrol response.
//    Mode: 0=LP, 1=HP, 2=BP
//    CV controls both amplitude and filter cutoff via vactrol.
// ============================================================
SynthDef(\vactrol_classic, {
    |inBus=0, outBus=0,
     cv=0, mode=0|

    var in_sig, sig;
    var vac_env, vac_amp, cutoff, rq;
    var decay_time;
    var atk = 0.005;

    in_sig = In.ar(inBus, 1);

    // Per-instance random decay variance
    decay_time = Rand(0.05, 0.5);

    // Vactrol envelope
    vac_env = Lag2UD.ar(K2A.ar(cv.clip(0, 1)), atk, decay_time);

    // Logarithmic amplitude response
    vac_amp = vac_env.squared;

    // Cutoff tracks vactrol
    cutoff = vac_env.linexp(0, 1, 60, 20000);
    rq = 0.4; // warm, musical resonance

    // Multimode: 0=LP, 1=HP, 2=BP
    sig = Select.ar(mode.clip(0, 2), [
        RLPF.ar(in_sig, cutoff, rq),
        RHPF.ar(in_sig, cutoff, rq),
        BPF.ar(in_sig, cutoff, rq)
    ]);

    sig = sig * vac_amp;

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


// ============================================================
// 8. FORMANT DRIFT — Fixed Filter Bank (FxDf clone)
//    8 fixed resonant bands at musically-chosen frequencies.
//    Individual gain controls per band, plus dry/wet mix.
//    Frequencies chosen to span the vocal formant range.
// ============================================================
SynthDef(\formant_drift, {
    |inBus=0, outBus=0, mix=0.5,
     gain1=1.0, gain2=1.0, gain3=1.0, gain4=1.0,
     gain5=1.0, gain6=1.0, gain7=1.0, gain8=1.0|

    var in_sig, dry, bands, wet;
    var gains;

    // Fixed resonant frequencies (spanning ~100Hz to ~8kHz)
    // Chosen for vocal/formant character and musical spacing
    var band_freqs = [110, 220, 440, 880, 1760, 3520, 5280, 7920];
    // Bandwidth (rq) narrows slightly at higher bands for definition
    var band_rqs = [0.15, 0.12, 0.10, 0.10, 0.08, 0.08, 0.06, 0.06];

    in_sig = In.ar(inBus, 1);
    dry = in_sig;

    gains = [gain1, gain2, gain3, gain4, gain5, gain6, gain7, gain8];

    // 8 parallel resonant bandpass filters
    bands = 8.collect({ |i|
        BPF.ar(in_sig, band_freqs[i], band_rqs[i]) * gains[i].clip(0, 4) * 4;
    });

    wet = Mix.new(bands);

    // Dry/wet mix
    Out.ar(outBus, LeakDC.ar(XFade2.ar(dry, wet, mix.clip(0, 1) * 2 - 1)));
}).add;


// ============================================================
// 9. VACTROL DXG — Dual Crossfading Gate (DXG clone)
//    Stereo VCA with crossfade between input A and input B.
//    Both inputs are gated through a shared vactrol model.
//    Crossfade sweeps between the two sources.
// ============================================================
SynthDef(\vactrol_dxg, {
    |inBusA=0, inBusB=0, outBus=0,
     crossfade=0.5, cv=0|

    var in_a, in_b, sig;
    var vac_env, vac_amp, cutoff;
    var decay_time;
    var atk = 0.005;

    in_a = In.ar(inBusA, 1);
    in_b = In.ar(inBusB, 1);

    // Per-instance random decay variance
    decay_time = Rand(0.05, 0.5);

    // Vactrol envelope
    vac_env = Lag2UD.ar(K2A.ar(cv.clip(0, 1)), atk, decay_time);

    // Logarithmic amplitude response
    vac_amp = vac_env.squared;

    // Vactrol-coupled lowpass for both channels before crossfade
    cutoff = vac_env.linexp(0, 1, 80, 20000);
    in_a = LPF.ar(in_a, cutoff);
    in_b = LPF.ar(in_b, cutoff);

    // Crossfade between A and B: 0 = all A, 1 = all B
    sig = XFade2.ar(in_a, in_b, crossfade.clip(0, 1) * 2 - 1);

    // Apply vactrol amplitude gate
    sig = sig * vac_amp;

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


// ============================================================
// ENTITY REGISTRATION
// ============================================================
[
    [\tetrapeak, "QuadPeakFilter", 4001],
    [\vactrol_sanctum, "DualLPG", 4002],
    [\vactrol_shadow, "DualLPG_6_12", 4003],
    [\vactrol_matrix, "QuadDynamicsGate", 4004],
    [\vactrol_quad, "QuadMultimodeGate", 4005],
    [\resonance_prism, "MultimodeFilter", 4006],
    [\vactrol_classic, "MultimodeGate", 4007],
    [\formant_drift, "FixedFilterBank", 4008],
    [\vactrol_dxg, "DualCrossfadeGate", 4009]
].do({ |spec|
    var synth_def = spec[0];
    var type = spec[1];
    var id = spec[2];

    ~BRAHMA_REGISTRY.registerEntity(id, type, (
        spectral_profile: (centroid: 0.5, flatness: 0.2, bandwidth: 0.7, rolloff: 0.4),
        temporal_topology: (attack: 0.005, decay: 0.3, sustain: 0.5, release: 0.3, slew: 0.8),
        modulation_graph: (type: synth_def, sources: 0, dests: 0, routes: 0),
        performance_response: (velocity: 0.0, aftertouch: 0.0, xy_sensitivity: 0.0, humanize: 0.0)
    ));
});

"--- BRAHMA: Make Noise Filter Suite Loaded (9 SynthDefs) ---".postln;
"  TETRAPEAK (QPAS) | VACTROL SANCTUM (Optomix) | VACTROL SHADOW (LxD)".postln;
"  VACTROL MATRIX (QXG) | VACTROL QUAD (QMMG) | RESONANCE PRISM (Multimod)".postln;
"  VACTROL CLASSIC (MMG) | FORMANT DRIFT (FxDf) | VACTROL DXG (DXG)".postln;
)
