/*
  Fidelity Stacking Absorption Protocol (FSAP)
  State Machine for Cumulative Integration
*/

FSAP {
    var <state;
    var <stack; // List of TraitMaps
    var <currentObservation;
    
    *new {
        ^super.new.init;
    }
    
    init {
        state = \IDLE;
        stack = List.new;
    }
    
    // 1. Observation Phase (guarded: must be IDLE)
    observe { |targetId, registry|
        if (state == \IDLE) {
            state = \OBSERVING;
            currentObservation = registry.getTraits(targetId);
            "FSAP: Observed %".format(targetId).postln;
        } {
            "FSAP Error: Must be IDLE to observe (current: %)".format(state).warn;
        };
    }
    
    // 2. Absorption Phase
    absorb {
        if (state == \OBSERVING) {
            state = \ABSORBING;
            "FSAP: Absorbed target".postln;
        } {
            "FSAP Error: Must observe before absorbing".warn;
        };
    }
    
    // 3. Integration Phase
    integrate { |fidelity=1.0|
        if (state == \ABSORBING) {
            if (AdamKadmon.validateTraitMap(currentObservation)) {
                state = \INTEGRATING;
                currentObservation = AdamKadmon.normalize(currentObservation);
                "FSAP: Integrated with fidelity %".format(fidelity).postln;
            } {
                "FSAP Error: TraitMap failed AdamKadmon validation".warn;
                state = \IDLE;
            }
        }
    }
    
    // 4. Accumulation Phase
    accumulate {
        if (state == \INTEGRATING) {
            state = \ACCUMULATING;
            stack.add(currentObservation);
            "FSAP: Accumulated. Stack depth: %".format(stack.size).postln;
            state = \IDLE; // Cycle complete
        }
    }
}
