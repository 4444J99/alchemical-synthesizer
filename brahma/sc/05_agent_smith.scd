/*
  Agent Smith: Self-Replicating Signal Intelligence
  Core Logic: Identity Engines & Clone Bus
*/

(
SynthDef(\agent_smith_identity, {
    |outBus=0, freq=440, phase=0, replicationCount=1, dominance=0.0|
    
    var sig, oscillators, leaders, replicas;
    
    // Identity Engines (Identity = Shared Phase/Waveform)
    // Polyphony = Replication
    oscillators = Array.fill(replicationCount.clip(1, 8), { |i|
        var ph = phase + (i * 0.001 * (1 - dominance)); // Shared phase with slight detune unless dominant
        Pulse.ar(freq, 0.5, 0.1);
    });
    
    // Clone Bus (Homogeneity Enforcement)
    sig = oscillators.sum;
    
    // clinical LowPass
    sig = LPF.ar(sig, 2000 + (dominance * 8000));
    
    // Digital clipping (System Violence)
    sig = (sig * (1 + (dominance * 10))).tanh;
    
    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: Agent Smith Loaded ---".postln;
)
