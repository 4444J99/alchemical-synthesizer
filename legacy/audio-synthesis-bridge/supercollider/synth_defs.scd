/*
 * Omni-Performative Engine — Synth Definitions
 *
 * Three-layer synthesis architecture:
 *   1. Drone: Sustained harmonic foundation
 *   2. Granular: Textural complexity layer
 *   3. Rhythm: Percussive pulse layer
 *
 * All synths respond to parameters from audience consensus:
 *   - intensity → amplitude, filter brightness
 *   - density → grain rate, rhythmic complexity
 *   - pitch → fundamental frequency, harmonic series
 */

(
// ============================================================================
// Layer 1: DRONE — Harmonic Foundation
// ============================================================================

SynthDef(\opeDrone, {
    arg freq = 110, amp = 0.3, cutoff = 2000, gate = 1;
    var sig, env, harmonics;
    
    // Generate harmonic series
    harmonics = Array.fill(6, { |i|
        var harmFreq = freq * (i + 1);
        var harmAmp = 1 / (i + 1).sqrt;
        SinOsc.ar(harmFreq * LFNoise1.kr(0.1).range(0.998, 1.002), 0, harmAmp)
    }).sum;
    
    // Add subtle movement
    harmonics = harmonics * LFTri.kr(0.1).range(0.8, 1.0);
    
    // Low-pass filter controlled by intensity
    sig = LPF.ar(harmonics, cutoff);
    
    // Slow amplitude envelope
    env = EnvGen.kr(Env.asr(2, 1, 3), gate, doneAction: 2);
    
    // Stereo spread
    sig = Splay.ar(sig, 0.5);
    
    Out.ar(0, sig * amp * env);
}).add;

// ============================================================================
// Layer 2: GRANULAR — Textural Complexity
// ============================================================================

SynthDef(\opeGranular, {
    arg rate = 5, amp = 0.2, gate = 1;
    var sig, env, trig, grains;
    
    // Trigger grains at variable rate
    trig = Impulse.kr(rate);
    
    // Generate grains from noise bursts
    grains = Array.fill(4, {
        var grainFreq = TExpRand.kr(200, 2000, trig);
        var grainDur = TRand.kr(0.01, 0.1, trig);
        var grainPan = TRand.kr(-1, 1, trig);
        
        var grain = SinOsc.ar(grainFreq) * 
            EnvGen.ar(Env.perc(0.001, grainDur), trig);
        
        Pan2.ar(grain, grainPan)
    }).sum;
    
    // High-pass to avoid mud
    sig = HPF.ar(grains, 400);
    
    // Envelope
    env = EnvGen.kr(Env.asr(0.5, 1, 1), gate, doneAction: 2);
    
    Out.ar(0, sig * amp * env);
}).add;

// ============================================================================
// Layer 3: RHYTHM — Percussive Pulse
// ============================================================================

SynthDef(\opeRhythm, {
    arg density = 2, freq = 110, amp = 0.15, gate = 1;
    var sig, env, trig, kick, hat;
    
    // Trigger at density-controlled rate
    trig = Impulse.kr(density);
    
    // Kick-like element (follows pitch)
    kick = SinOsc.ar(freq * 0.5) * 
        EnvGen.ar(Env.perc(0.001, 0.2), trig) *
        0.8;
    kick = kick + (
        SinOsc.ar(freq * 2) * 
        EnvGen.ar(Env.perc(0.001, 0.05), trig) *
        0.3
    );
    
    // Hi-hat-like noise burst
    hat = WhiteNoise.ar * 
        EnvGen.ar(Env.perc(0.001, 0.03), TDelay.kr(trig, 0.05)) *
        0.2;
    hat = HPF.ar(hat, 8000);
    
    sig = kick + hat;
    
    // Envelope
    env = EnvGen.kr(Env.asr(0.1, 1, 0.5), gate, doneAction: 2);
    
    // Stereo
    sig = Pan2.ar(sig, LFNoise1.kr(0.2).range(-0.3, 0.3));
    
    Out.ar(0, sig * amp * env);
}).add;

// ============================================================================
// Utility: Test Synths
// ============================================================================

SynthDef(\opeTest, {
    arg freq = 440, amp = 0.3, dur = 1;
    var sig, env;
    
    sig = SinOsc.ar(freq);
    env = EnvGen.kr(Env.perc(0.01, dur), doneAction: 2);
    
    Out.ar(0, Pan2.ar(sig * amp * env, 0));
}).add;

// ============================================================================
// Initialization Message
// ============================================================================

"╔══════════════════════════════════════════════════════════════╗".postln;
"║     Synth Definitions Loaded                                 ║".postln;
"╠══════════════════════════════════════════════════════════════╣".postln;
"║  Available synths:                                           ║".postln;
"║    \\opeDrone    - Harmonic foundation layer                  ║".postln;
"║    \\opeGranular - Textural grain layer                       ║".postln;
"║    \\opeRhythm   - Percussive pulse layer                     ║".postln;
"║    \\opeTest     - Simple test tone                           ║".postln;
"╠══════════════════════════════════════════════════════════════╣".postln;
"║  Quick test:                                                 ║".postln;
"║    Synth(\\opeTest);                                          ║".postln;
"╚══════════════════════════════════════════════════════════════╝".postln;

)
