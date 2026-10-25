/*
  TransmutationEngine — Cross-Substrate Trait Transmutation
  
  Operator algebra: absorb(donor) → traits → transmute(targetSubstrate) → re-express
  
  Works with proxy traits until FluidBufSpectralShape (Flucoma) is installed,
  at which point the same operators accept measured traits. Operators are
  substrate-specific: spectral→harmonic, envelope→rhythm, modulation→edge,
  response→shift.
*/

TransmutationEngine {
    classvar <operators = Dictionary.new;   // operator name -> function
    classvar <substrateMap = Dictionary.new; // substrate name -> trait axis mapping
    
    // --- Register an operator ---
    //   name: operator symbol
    //   fn: { |traits, fromSubstrate, toSubstrate| -> transformedTraits }
    *registerOperator { |name, fn|
        ~operators[name] = fn;
        ("Transmutation: Registered operator %".format(name)).postln;
    }
    
    // --- Map substrate trait axes ---
    *mapSubstrate { |substrate, axisMap|
        ~substrateMap[substrate] = axisMap;
    }
    
    // --- Absorb a donor: validate its trait map through AdamKadmon ---
    *absorb { |traitMap, fromSubstrate|
        // Validate against the source substrate's contract
        var valid = AdamKadmon.validateTraitMapWithProvenance(
            traitMap, fromSubstrate, \proxy, 0.7
        );
        if (valid.not) {
            ("Transmutation: Absorb rejected — trait map failed validation for %".format(fromSubstrate)).warn;
            ^nil;
        };
        var normalized = AdamKadmon.normalize(traitMap, fromSubstrate);
        ("Transmutation: Absorbed % donor traits".format(fromSubstrate)).postln;
        ^normalized;
    }
    
    // --- Transmute absorbed traits into a target substrate ---
    *transmute { |normalizedTraits, fromSubstrate, toSubstrate, operatorName|
        operatorName = if (operatorName.notNil) { operatorName } { \default };
        
        var op = ~operators.at(operatorName);
        if (op.isNil) {
            ("Transmutation: Unknown operator % — using identity".format(operatorName)).warn;
            op = { |t, f, t2| t.copy };
        };
        
        var result = op.value(normalizedTraits, fromSubstrate, toSubstrate);
        
        // Validate the result against the target substrate's contract
        var resultValid = AdamKadmon.validateTraitMapWithProvenance(
            result, toSubstrate, \proxy, 0.7
        );
        if (resultValid.not) {
            ("Transmutation: Result failed validation for % — returning best-effort".format(toSubstrate)).warn;
        };
        
        ("Transmutation: % → % via %".format(fromSubstrate, toSubstrate, operatorName)).postln;
        ^result;
    }
    
    // --- Built-in operators ---
    *initOperators {
        // spectral→harmonic: map spectral profile to harmonic content
        ~operators[\spectralToHarmonic] = { |traits, from, to|
            var result = traits.copy;
            // Spectral profile → emphasize harmonic structure
            if (traits[\spectral_profile].notNil) {
                result[\spectral_profile] = traits[\spectral_profile] * 0.8 + 0.2;
            };
            result
        };
        
        // envelope→rhythm: map temporal topology to rhythmic density
        ~operators[\envelopeToRhythm] = { |traits, from, to|
            var result = traits.copy;
            if (traits[\temporal_topology].notNil) {
                result[\temporal_topology] = traits[\temporal_topology] * 0.9;
            };
            result
        };
        
        // modulation→edge: map modulation graph to connection edges
        ~operators[\modulationToEdge] = { |traits, from, to|
            var result = traits.copy;
            if (traits[\modulation_graph].notNil) {
                result[\modulation_graph] = traits[\modulation_graph] * 0.85 + 0.1;
            };
            result
        };
        
        // response→shift: map performance response to parameter shift
        ~operators[\responseToShift] = { |traits, from, to|
            var result = traits.copy;
            if (traits[\performance_response].notNil) {
                result[\performance_response] = traits[\performance_response] * 0.95;
            };
            result
        };
        
        // default: identity (pass traits through unchanged)
        ~operators[\default] = { |traits, from, to| traits.copy };
    }
    
    // --- Map each substrate's trait axes to canonical keys ---
    *initSubstrateMap {
        // All four substrates use the same canonical four keys, just with
        // different labels. The mapping is identity for now; substrate-specific
        // axis transforms can be added here.
        ~substrateMap[\sound] = Dictionary.newFromPairs([
            #[\spectral_profile -> \spectral_profile,
              \temporal_topology -> \temporal_topology,
              \modulation_graph -> \modulation_graph,
              \performance_response -> \performance_response]
        ]);
        ~substrateMap[\idea] = ~substrateMap[\sound].deepCopy;
        ~substrateMap[\product] = ~substrateMap[\sound].deepCopy;
        ~substrateMap[\cosmos] = ~substrateMap[\sound].deepCopy;
    }
    
    // --- Initialize ---
    *init {
        ~initOperators;
        ~initSubstrateMap;
        ("TransmutationEngine: initialized with % operators".format(~operators.size)).postln;
    }
    
    // --- List available operators ---
    *operatorsList {
        ^~operators.keys.asArray;
    }
}

// Auto-initialize on class load
TransmutationEngine.init;