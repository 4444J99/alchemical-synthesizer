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
    classvar <contracts;   // name -> contract dict

    *initClass { contracts = Dictionary.new; }
    
    // --- Canonical Schema Definition (default, fallback) ---
    *validateTraitMap { |map, contractName|
        var contract = this.contractFor(contractName);
        ^BrahmaContracts.validate(map, contract, strictness);
    }
    
    *normalize { |map, contractName|
        ^BrahmaContracts.normalize(map, this.contractFor(contractName));
    }
    
    *loadContract { |path|
        var contract = BrahmaContracts.load(path);
        if(contract.isNil) { ^nil };
        contracts[contract[\name].asSymbol] = contract;
        ^contract[\name].asSymbol;
    }
    
    *contractNames {
        ^contracts.keys.asArray;
    }

    *contractFor { |name|
        if(name.isNil or: { name.asSymbol == \canonical_v1 }) { ^this.defaultContract };
        ^contracts[name.asSymbol];
    }

    *validateMeasurement { |map|
        ^BrahmaContracts.validMeasurement(map, strictness);
    }
    
    *checkPermission { |srcId, dstId, mode|
        // mode: read, write, infect
        // Simple mock permission logic
        // In full implementation, this would check the Registry contracts
        ^true;
    }
    
    *issueCapabilityToken { |entityId, capability|
        // Issue a signed token for an action
        // Correlation identifier only; this is not a signed authorization token.
        ^[entityId, capability, Date.getDate.rawSeconds].asCompileString.hash;
    }
    
    *defaultContract {
        ^(name: \canonical_v1,
            requiredKeys: [\spectral_profile, \temporal_topology, \modulation_graph, \performance_response],
            ranges: ());
    }
}
