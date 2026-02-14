/*
  Phase 4: The Absorption-Fusion Loop
  Module: FUSION CORE & NUCLEUS
*/

(
// ------------------------------------------------------------
// FUSION CORE: Binding + Emergent Operator
// ------------------------------------------------------------

SynthDef(\fusion_core_voice, {
    |inBusA=0, inBusB=1, outBus=0,
     bind=0.5, dominance=0.0, symmetry=0.5, mutation=0.1|
    
    var a, b, sig, modA, modB, combined, physiology, psychology;
    
    a = In.ar(inBusA, 1);
    b = In.ar(inBusB, 1);
    
    // 1. Morphology (Binding)
    // Dominance shifts the mix balance
    // Symmetry affects how much A modulates B vs B modulates A
    
    modA = a * (1 - symmetry + (dominance * 0.5)).clip(0,1);
    modB = b * (symmetry + (dominance * 0.5)).clip(0,1);
    
    // Cross-Modulation (Ring/AM) proportional to Bind
    a = a + (modB * bind * a);
    b = b + (modA * bind * b);
    
    combined = XFade2.ar(a, b, dominance);
    
    // 2. Physiology (Dynamics/Saturation)
    physiology = tanh(combined * (1 + (bind * 2)));
    
    // 3. Psychology (Mutation/Drift)
    // LFOs derived from signal energy
    psychology = LFNoise1.kr(1 + (mutation * 10));
    
    // Apply mutation to filter
    sig = RLPF.ar(physiology,
        combined.linexp(-1, 1, 100, 5000) * (1 + (psychology * mutation)),
        0.5
    );

    // Safety limiter: cross-modulation can produce unbounded signals
    sig = Limiter.ar(sig, 0.95, 0.01);

    Out.ar(outBus, sig);
}).add;

// ------------------------------------------------------------
// NUCLEUS: Genome Capture (Stub)
// ------------------------------------------------------------
// Nucleus is primarily a data structure (Dictionary) in the Language side.
// This SynthDef is a "Freezer" that loops a granule of audio.

SynthDef(\nucleus_freeze, {
    |inBus=0, outBus=0, freeze=0, buf|
    var in, rec, play;
    
    in = In.ar(inBus, 1);
    
    // Record when NOT frozen
    rec = RecordBuf.ar(in, buf, 0, 1, 0, 1 - freeze, loop: 1);
    
    // Playback
    play = PlayBuf.ar(1, buf, 1, loop: 1);
    
    Out.ar(outBus, play * freeze);
}).add;

"--- BRAHMA: Fusion Core & Nucleus Definitions Loaded ---".postln;
)
