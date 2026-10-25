/*
  TransmutationEngine — Cross-Substrate Trait Transmutation
  
  Operator algebra: absorb(donor) → traits → transmute(targetSubstrate) → re-express
  
  Works with proxy traits until FluidBufSpectralShape (Flucoma) is installed,
  at which point the same operators accept measured traits. Operators are
  substrate-specific: spectral→harmonic, envelope→rhythm, modulation→edge,
  response→shift.
*/

TransmutationEngine {
    classvar <operators;   // operator name -> function
    classvar <substrateMap; // substrate name -> trait axis mapping
    
    *initClass {
        operators = Dictionary.new;
        substrateMap = Dictionary.new;
        this.init;
    }

    // --- Register an operator ---
    //   name: operator symbol
    //   fn: { |traits, fromSubstrate, toSubstrate| -> transformedTraits }
    *registerOperator { |name, fn|
        operators[name] = fn;
        ("Transmutation: Registered operator %".format(name)).postln;
    }
    
    // --- Map substrate trait axes ---
    *mapSubstrate { |substrate, axisMap|
        substrateMap[substrate] = axisMap;
    }
    
    // --- Absorb a donor: validate its trait map through AdamKadmon ---
    *absorb { |traitMap, fromSubstrate|
        // Validate against the source substrate's contract
        var normalized;
        var valid = AdamKadmon.validateTraitMapWithProvenance(
            traitMap, fromSubstrate, \proxy, 0.7
        );
        if (valid.not) {
            ("Transmutation: Absorb rejected — trait map failed validation for %".format(fromSubstrate)).warn;
            ^nil;
        };
        normalized = AdamKadmon.normalize(traitMap, fromSubstrate);
        ("Transmutation: Absorbed % donor traits".format(fromSubstrate)).postln;
        ^normalized;
    }
    
    // --- Transmute absorbed traits into a target substrate ---
    *transmute { |normalizedTraits, fromSubstrate, toSubstrate, operatorName|
        var op, result, resultValid;
        operatorName = if (operatorName.notNil) { operatorName } { \default };
        op = operators.at(operatorName);
        if (op.isNil) {
            ("Transmutation: Unknown operator % — using identity".format(operatorName)).warn;
            op = { |t, f, t2| t.copy };
        };
        
        result = op.value(normalizedTraits.deepCopy, fromSubstrate, toSubstrate);
        if(result.isKindOf(Dictionary).not) { ^nil };
        if((fromSubstrate != toSubstrate) or: { result != normalizedTraits }) {
            // A changed identity must be remeasured; donor evidence does not
            // attest to transformed output. FSAP must not accept stale proof.
            result = result.copy.put(\provenance, \proxy).put(\confidence, 0.7);
            result.removeAt(\measurements);
        };
        
        // Validate the result against the target substrate's contract
        resultValid = AdamKadmon.validateTraitMapWithProvenance(
            result, toSubstrate, \proxy, 0.7
        );
        if (resultValid.not) {
            ("Transmutation: Result failed validation for % — rejecting invalid output".format(toSubstrate)).warn;
            ^nil;
        };
        
        ("Transmutation: % → % via %".format(fromSubstrate, toSubstrate, operatorName)).postln;
        ^result;
    }
    
    // --- Built-in operators ---
    *mapDimension { |value, function|
        if(value.isNumber) { ^function.value(value).clip(0, 1) };
        if(value.isKindOf(Dictionary)) { ^value.collect { |item| this.mapDimension(item, function) } };
        if(value.isArray and: { value.isKindOf(String).not }) { ^value.collect { |item| this.mapDimension(item, function) } };
        ^value;
    }

    *initOperators {
        // spectral→harmonic: map spectral profile to harmonic content
        operators[\spectralToHarmonic] = { |traits, from, to|
            var result = traits.copy;
            // Spectral profile → emphasize harmonic structure
            if (traits[\spectral_profile].notNil) {
                result[\spectral_profile] = this.mapDimension(traits[\spectral_profile], { |value| value * 0.8 + 0.2 });
            };
            result
        };
        
        // envelope→rhythm: map temporal topology to rhythmic density
        operators[\envelopeToRhythm] = { |traits, from, to|
            var result = traits.copy;
            if (traits[\temporal_topology].notNil) {
                result[\temporal_topology] = this.mapDimension(traits[\temporal_topology], { |value| value * 0.9 });
            };
            result
        };
        
        // modulation→edge: map modulation graph to connection edges
        operators[\modulationToEdge] = { |traits, from, to|
            var result = traits.copy;
            if (traits[\modulation_graph].notNil) {
                result[\modulation_graph] = this.mapDimension(traits[\modulation_graph], { |value| value * 0.85 + 0.1 });
            };
            result
        };
        
        // response→shift: map performance response to parameter shift
        operators[\responseToShift] = { |traits, from, to|
            var result = traits.copy;
            if (traits[\performance_response].notNil) {
                result[\performance_response] = this.mapDimension(traits[\performance_response], { |value| value * 0.95 });
            };
            result
        };
        
        // default: identity (pass traits through unchanged)
        operators[\default] = { |traits, from, to| traits.copy };
    }
    
    // --- Map each substrate's trait axes to canonical keys ---
    *initSubstrateMap {
        // All four substrates use the same canonical four keys, just with
        // different labels. The mapping is identity for now; substrate-specific
        // axis transforms can be added here.
        substrateMap[\sound] = (spectral_profile: \spectral_profile,
            temporal_topology: \temporal_topology, modulation_graph: \modulation_graph,
            performance_response: \performance_response);
        substrateMap[\idea] = substrateMap[\sound].deepCopy;
        substrateMap[\product] = substrateMap[\sound].deepCopy;
        substrateMap[\cosmos] = substrateMap[\sound].deepCopy;
    }
    
    // --- Initialize ---
    *init {
        this.initOperators;
        this.initSubstrateMap;
        ("TransmutationEngine: initialized with % operators".format(operators.size)).postln;
    }
    
    // --- List available operators ---
    *operatorsList {
        ^operators.keys.asArray;
    }
}

// Class initialization is handled by initClass above.
