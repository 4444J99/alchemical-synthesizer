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
    
    // 1. Observation Phase
    observe { |targetId, registry|
        state = \OBSERVING;
        // Mock observation logic
        currentObservation = registry.getTraits(targetId);
        "FSAP: Observed %".format(targetId).postln;
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
            state = \INTEGRATING;
            // Apply fidelity loss
            // In a real system, this would degrade the trait map
            "FSAP: Integrated with fidelity %".format(fidelity).postln;
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
