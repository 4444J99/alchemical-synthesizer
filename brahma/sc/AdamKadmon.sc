/*
  Adam Kadmon: The Primordial Schema Body
  Ontological Integrator and Trait Validator
  
  JSON-based contract system:
  - Contracts are JSON files defining trait schemas, required keys, ranges, and strictness thresholds.
  - loadContract(path) reads + parses a JSON contract file into ~contracts.
  - validateTraitMap(map, contractName) validates a trait map against a named contract.
  - normalize(map, contractName) normalizes a trait map using a named contract's ranges.
  - contractNames() returns the list of loaded contract names.
*/

AdamKadmon {
    classvar <ontologyProfile = 'canonical_v1';
    classvar <strictness = 0.85;
    classvar <contracts = Dictionary.new;   // name -> contract dict
    
    // --- Canonical Schema Definition (default, fallback) ---
    *validateTraitMap { |map, contractName|
        var contract = if (contractName.notNil) { ~contracts.at(contractName) } { nil };
        contract = if (contract.notNil) { contract } { ~defaultContract };
        var valid = true;
        var requiredKeys = contract[\requiredKeys] ?? [\spectral_profile, \temporal_topology, \modulation_graph, \performance_response];
        
        requiredKeys.do { |key|
            if (map.includesKey(key).not) {
                ("AdamKadmon: Missing required trait dimension: " ++ key).warn;
                valid = false;
            };
        };
        
        // Type + range validation when contract provides them
        contract[\ranges].doIfNotNil { |ranges|
            ranges.do { |key, spec|
                if (map.includesKey(key)) {
                    var v = map[key];
                    var lo = spec[\min] ?? 0.0;
                    var hi = spec[\max] ?? 1.0;
                    if (v < lo or: { v > hi }) {
                        ("AdamKadmon: Trait " ++ key ++ " = " ++ v ++ " outside range [" ++ lo ++ ", " ++ hi ++ "]").warn;
                        valid = false;
                    };
                };
            };
        };
        
        ^valid;
    }
    
    *normalize { |map, contractName|
        var contract = if (contractName.notNil) { ~contracts.at(contractName) } { nil };
        contract = if (contract.notNil) { contract } { ~defaultContract };
        var newMap = map.deepCopy;
        
        contract[\ranges].doIfNotNil { |ranges|
            ranges.do { |key, spec| 
                if (newMap.includesKey(key)) {
                    var lo = spec[\min] ?? 0.0;
                    var hi = spec[\max] ?? 1.0;
                    newMap[key] = newMap[key].clip(lo, hi);
                };
            };
        };
        
        // Default normalization for spectral profile (back-compat)
        if (newMap[\spectral_profile].notNil) {
            newMap[\spectral_profile].keysValuesChange { |k, v|
                v.clip(0.0, 1.0);
            };
        };
        
        ^newMap;
    }
    
    *loadContract { |path|
        var file = File(path, "r");
        var contract;
        if (file.exists) {
            contract = JSON.parse(file.readAllString);
            file.close;
            if (contract.notNil and: { contract[\name].notNil }) {
                ~contracts[contract[\name]] = contract;
                ("AdamKadmon: Loaded contract '" ++ contract[\name] ++ "' from " ++ path).postln;
                ^contract[\name];
            } {
                file.close;
                ("AdamKadmon: Contract at " ++ path ++ " missing 'name' field").warn;
                ^nil;
            };
        } {
            ("AdamKadmon: Contract file not found: " ++ path).warn;
            file.close;
            ^nil;
        };
    }
    
    *contractNames {
        ^~contracts.keys.asArray;
    }
    
    *checkPermission { |srcId, dstId, mode|
        // mode: read, write, infect
        // Simple mock permission logic
        // In full implementation, this would check the Registry contracts
        ^true;
    }
    
    *issueCapabilityToken { |entityId, capability|
        // Issue a signed token for an action
        ^Hash.new((entityId ++ capability ++ Date.getDate).asString);
    }
    
    *defaultContract {
        ^Dictionary.newFromPairs([
            #[\name -> "canonical_v1",
              \requiredKeys -> [\spectral_profile, \temporal_topology, \modulation_graph, \performance_response],
              \ranges -> Dictionary.newFromPairs([
                  #[\spectral_profile -> (\min -> 0.0, \max -> 1.0),
                    \temporal_topology -> (\min -> 0.0, \max -> 1.0),
                    \modulation_graph -> (\min -> 0.0, \max -> 1.0),
                    \performance_response -> (\min -> 0.0, \max -> 1.0)]
              ])
        ]);
    }
}