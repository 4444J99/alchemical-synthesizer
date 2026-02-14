/*
  Phase 6: Typhon (The Accumulator)
*/

(
SynthDef(	yphon_layer, {
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
    
    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: Typhon Definition Loaded ---".postln;
)
