/*
  Phase 7: Safety & Stability
  IMMUNE & METABOLISM
*/

(
// ------------------------------------------------------------
// IMMUNE (The Governor)
// ------------------------------------------------------------
SynthDef(\immune_governor, {
    |inBus=0, outBus=0, threshold=0.9, autoQuarantine=1|
    
    var in, amp, gate, sig;
    
    in = In.ar(inBus, 1);
    
    // DC Blocking
    in = LeakDC.ar(in);
    
    // Feedback/Runaway Detection
    amp = Amplitude.kr(in, 0.05, 0.05);
    
    // Quarantine Gate (Mute if unsafe)
    gate = (amp < threshold).lag(0.1);
    
    sig = in * gate;
    
    // Hard Limiter
    sig = Limiter.ar(sig, threshold, 0.01);
    
    Out.ar(outBus, sig);
}).add;

// ------------------------------------------------------------
// METABOLISM (Macro-Dynamics)
// ------------------------------------------------------------
SynthDef(\metabolism_engine, {
    |outBusPhase=0, outBusGlucose=1, 
     cycleDur=10, thermalDrift=0.1|
    
    var phase, glucose, drift;
    
    // Cell Cycle Phase (0..1 saw)
    phase = LFSaw.kr(1/cycleDur, 1).unipolar;
    
    // Glucose (Energy available) - Peaks in middle of cycle
    glucose = SinOsc.kr(1/cycleDur, 1.5pi).unipolar;
    
    // Thermal Drift (Brownian motion)
    drift = LFNoise1.kr(0.1).bipolar(thermalDrift);
    
    Out.kr(outBusPhase, phase);
    Out.kr(outBusGlucose, (glucose + drift).clip(0,1));
}).add;

"--- BRAHMA: Safety & Metabolism Loaded ---".postln;
)
