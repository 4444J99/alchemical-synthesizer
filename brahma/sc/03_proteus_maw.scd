/*
  Phase 3: Core Analytical Organisms
  Proteus (The Form-Knower) & MAW (Digestive Intake)
*/

(
// ------------------------------------------------------------
// PROTEUS: Analysis & Resynthesis
// ------------------------------------------------------------

SynthDef(\proteus_analyze, {
    |inBus=0, outBusEnv=0, outBusTone=1, outBusNoise=2, outBusTrans=3,
     obsFocus=0.7, morphLatency=0.035|
    
    var in, chain, centroid, flat, amp, onset, features;
    
    in = In.ar(inBus, 1);
    
    // FFT Analysis
    chain = FFT(LocalBuf(1024), in);
    centroid = SpecCentroid.kr(chain);
    flat = SpecFlatness.kr(chain);
    amp = Amplitude.kr(in, 0.01, 0.1);
    onset = Onsets.kr(chain, 0.5);
    
    // Smoothing (Morph Latency)
    centroid = Lag.kr(centroid, morphLatency);
    flat = Lag.kr(flat, morphLatency);
    amp = Lag.kr(amp, morphLatency);
    
    // Mapping to Normalized Traits (0..1)
    Out.kr(outBusEnv, amp.ampdb.linlin(-60, 0, 0, 1).clip(0,1));
    Out.kr(outBusTone, centroid.linlin(20, 10000, 0, 1).clip(0,1));
    Out.kr(outBusNoise, flat.clip(0,1));
    Out.kr(outBusTrans, onset);
}).add;

SynthDef(\proteus_render, {
    |outBus=0, inBusEnv=0, inBusTone=1, inBusNoise=2, 
     fidelity=0.92, shapeSlope=0.2|
    
    var env, tone, noise, sig, osc, filteredNoise;
    
    env = In.kr(inBusEnv, 1);
    tone = In.kr(inBusTone, 1);
    noise = In.kr(inBusNoise, 1);
    
    // Simple Resynthesis Model (Placeholder for Emulation Engine)
    // 1. Tonal Component (Sine)
    osc = SinOsc.ar(tone.linexp(0, 1, 50, 5000));
    
    // 2. Noise Component (Pink Noise)
    filteredNoise = BPF.ar(PinkNoise.ar, tone.linexp(0, 1, 100, 8000), 0.5);
    
    // Mixing based on "Noise" trait
    sig = XFade2.ar(osc, filteredNoise, (noise * 2) - 1);
    
    // Amplitude Envelope
    sig = sig * env;
    
    // Fidelity Degradation (Bitcrush/SampleRate if fidelity < 1)
    sig = Select.ar(fidelity < 0.99, [
        sig,
        Decimator.ar(sig, 44100 * fidelity, 24 * fidelity)
    ]);
    
    Out.ar(outBus, sig);
}).add;

// ------------------------------------------------------------
// MAW: Digestive Intake
// ------------------------------------------------------------

SynthDef(\maw_digest, {
    |inBus=0, outBusAudio=0, outBusCvStart=10, 
     hunger=0.5, bile=0.2|
    
    var in, features, digestedCv, essenceAudio;
    var chain, centroid;
    
    in = In.ar(inBus, 1);
    
    // Feature Extraction
    chain = FFT(LocalBuf(1024), in);
    centroid = SpecCentroid.kr(chain);
    
    // Digestion (Hunger = Quantization/Extraction Aggression)
    // High hunger = coarser steps in CV
    digestedCv = centroid.linlin(20, 10000, 0, 1);
    digestedCv = Latch.kr(digestedCv, Impulse.kr(50 * (1 - hunger)));
    digestedCv = Slew.kr(digestedCv, bile, bile);
    
    // Essence Audio (Stripped down version)
    // E.g. Spectral gating
    essenceAudio = PV_MagAbove(chain, hunger * 10);
    essenceAudio = IFFT(essenceAudio);
    
    Out.ar(outBusAudio, essenceAudio);
    Out.kr(outBusCvStart, digestedCv); // Example: just sending centroid
}).add;

"--- BRAHMA: Proteus & MAW Definitions Loaded ---".postln;
)
