/*
  Phase 6: Typhon (The Accumulator)
*/

(
SynthDef(\typhon_layer, {
    |inBus=0, outBus=0, modBusIn=0, modBusOut=0,
     dominance=0.0, crossCouple=0.0|

    var in, modIn, sig;

    in = In.ar(inBus, 1);
    modIn = In.ar(modBusIn, 1);

    // Write to modulation bus for other layers
    Out.ar(modBusOut, in * crossCouple);

    // Apply incoming modulation
    sig = in * (1 + (modIn * crossCouple));

    // Dominance scaling
    sig = sig * (1 + dominance);

    // Safety limiter: dominance + crossCouple can produce unbounded signals
    sig = Limiter.ar(sig, 0.95, 0.01);

    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: Typhon Definition Loaded ---".postln;
)
