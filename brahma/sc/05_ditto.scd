/*
  Ditto: Context-Reactive Morphic Engine
  Imitation under constraint.
*/

(
SynthDef(\ditto_morphic_core, {
    |inBus=0, outBus=0, observe=0.5, assume=0.5, mutate=0.1|
    
    var in, chain, centroid, amp, sig, kernel;
    
    in = In.ar(inBus, 1);
    chain = FFT(LocalBuf(1024), in);
    centroid = SpecCentroid.kr(chain);
    amp = Amplitude.kr(in);
    
    // Morphic Kernel (Polymorphic Oscillator)
    // Kernel reconfigures based on input amplitude and spectrum
    kernel = SelectX.ar(observe * 2, [
        VarSaw.ar(centroid.clip(20, 5000), 0, 0.5), // Tonal
        PinkNoise.ar(0.5) // Chaotic
    ]);
    
    // Error Engine (Structured Deviation)
    kernel = kernel + LFNoise1.ar(100, mutate * 0.1);
    
    // Assumption level (Commitment to role)
    sig = XFade2.ar(in, kernel, (assume * 2) - 1);
    
    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: Ditto Loaded ---".postln;
)
