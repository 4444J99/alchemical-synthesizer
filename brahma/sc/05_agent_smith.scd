/*
  Agent Smith: Self-Replicating Signal Intelligence
  Core Logic: Identity Engines & Clone Bus

  NOTE: Uses fixed 8-voice bank with amplitude gating controlled by
  replicationCount, since Array.fill with a UGen argument is evaluated
  at compile time (not runtime).
*/

(
SynthDef(\agent_smith_identity, {
    |outBus=0, freq=440, phase=0, replicationCount=1, dominance=0.0|

    var sig, oscillators;

    // Fixed 8-voice bank; amplitude gating controls active voice count
    oscillators = Array.fill(8, { |i|
        var active = (i < replicationCount).lag(0.01);
        var ph = phase + (i * 0.001 * (1 - dominance));
        Pulse.ar(freq, 0.5, 0.1) * active;
    });

    // Clone Bus (Homogeneity Enforcement)
    sig = oscillators.sum;

    // Clinical LowPass
    sig = LPF.ar(sig, 2000 + (dominance * 8000));

    // Digital clipping (System Violence)
    sig = (sig * (1 + (dominance * 10))).tanh;

    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: Agent Smith Loaded ---".postln;
)
