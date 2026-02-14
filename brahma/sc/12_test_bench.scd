/*
  Phase 12: The Evolutionary Crucible (A/B Test Bench)
  Comparing Organism Variations
*/

(
~TEST_BENCH = (
    
    // Compare two SynthDefs side-by-side
    runComparison: { |self, defA, defB, inputBus, duration=5|
        "--- STARTING A/B TEST: % vs % ---".format(defA, defB).postln;
        
        {
            var sigA, sigB;
            
            // 1. Run Version A
            "Running Version A...".postln;
            x = Synth(defA, [\inBus, inputBus, \outBus, ~SC_BUS.mainOut]); // Route to main for monitoring
            duration.wait;
            x.free;
            
            // 2. Run Version B
            "Running Version B...".postln;
            y = Synth(defB, [\inBus, inputBus, \outBus, ~SC_BUS.mainOut]);
            duration.wait;
            y.free;
            
            "--- A/B TEST COMPLETE ---".postln;
        }.fork;
    },
    
    // Auto-Variation Generator
    // Creates a temporary "mutated" version of a SynthDef to test against the stable one
    spawnMutant: { |self, baseDefName|
        var newName = (baseDefName ++ "_mutant").asSymbol;
        // In a full implementation, this would rewrite the UGen graph programmatically.
        // For now, it aliases the existing def for testing workflow.
        SynthDescLib.global[baseDefName.asSymbol].def.name_(newName).add;
        ^newName;
    }
);

"--- BRAHMA: A/B Test Bench Ready ---".postln;
)
