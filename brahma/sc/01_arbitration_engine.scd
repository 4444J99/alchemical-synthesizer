/*
  Brahma Meta-Rack: Server-Side Arbitration Engine
  Part of Phase 1 Refinement
*/

(
SynthDef(\brahma_bus_clock, {
    |tickHz=1000, outBusFlag=0, outBusClk=1|
    var tick, count;
    
    // 1kHz Master Tick
    tick = Impulse.ar(tickHz);
    
    // Emit pulses to Control Busses for inter-module sync
    Out.ar(outBusClk, tick);
    
    // Slot counting (0..7) for arbitration
    count = Stepper.ar(tick, 0, 0, 7);
    Out.kr(outBusFlag, count);
}).add;

SynthDef(\brahma_panic, {
    // Hard-mute: replace hardware outputs with silence
    ReplaceOut.ar(0, DC.ar(0) ! 2);
}).add;

"--- BRAHMA: Server-Side Arbitration Engine Loaded ---".postln;
)
