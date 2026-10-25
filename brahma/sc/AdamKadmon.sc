/*
  Adam Kadmon: The Primordial Schema Body
  Ontological Integrator and Trait Validator
  
  JSON-based contract system with provenance tracking:
  - Contracts are JSON files defining trait schemas, required keys, ranges, and strictness thresholds.
  - Contract parsing/validation lives in BrahmaContracts.sc; AdamKadmon is the
    ontology-facing wrapper that records validation provenance.
  - loadContract(path) reads + parses a JSON contract file into ~contracts.
  - validateTraitMap(map, contractName) validates a trait map against a named contract.
  - validateTraitMapWithProvenance(map, contractName, provenance, confidence)
      validates and records where the trait map came from
      (provenance: \measured / \proxy / \manual; confidence: 0..1).
  - normalize(map, contractName) normalizes a trait map using a named contract's ranges.
  - contractNames() returns the list of loaded contract names.
  - provenanceLog returns the full validation provenance log.
*/

AdamKadmon {
    classvar <ontologyProfile = 'canonical_v1';
    classvar <strictness = 0.85;        // gate threshold: traits below this fail validation
    classvar <contracts;                // name -> contract dict
    classvar provenanceLog; // list of {time, contract, valid, provenance, confidence, missingKeys}

    *initClass {
        contracts = Dictionary.new;
        provenanceLog = List.new;
    }

    // --- Resolve a named contract (fallback to canonical_v1) ---
    *contractFor { |contractName|
        if(contractName.isNil or: { contractName.asSymbol == \canonical_v1 }) { ^this.defaultContract };
        ^contracts[contractName.asSymbol] ? contracts[(contractName.asString ++ "_v1").asSymbol];
    }

    // --- Default canonical schema (fallback when no named contract) ---
    *defaultContract {
        ^(name: \canonical_v1,
            requiredKeys: [\spectral_profile, \temporal_topology, \modulation_graph, \performance_response],
            ranges: ());
    }

    // --- Validate a trait map against a named contract (manual provenance, full confidence) ---
    *validateTraitMap { |map, contractName|
        ^this.validateCore(map, this.contractFor(contractName), \manual, 1.0);
    }

    // --- Validate with provenance: records where the trait map came from ---
    //   provenance: \measured (real DSP / FluCoMa), \proxy (derived estimate), \manual (human-set)
    //   confidence: 0..1, how much we trust this map
    *validateTraitMapWithProvenance { |map, contractName, provenance, confidence|
        provenance = if (provenance.notNil) { provenance } { \manual };
        confidence = if (confidence.notNil) { confidence } { 1.0 };
        ^this.validateCore(map, this.contractFor(contractName), provenance, confidence);
    }

    // --- Internal: shared validation core that delegates to BrahmaContracts and records provenance ---
    *validateCore { |map, contract, provenance, confidence|
        var valid, missingKeys = List.new;
        valid = BrahmaContracts.validate(map, contract, strictness);
        if(map.isKindOf(Dictionary) and: { contract.notNil }) {
            contract[\requiredKeys].do { |key| if(map.includesKey(key).not) { missingKeys.add(key) } };
        };
        if(BrahmaContracts.finiteNumber(confidence).not) { valid = false } {
            valid = valid and: { confidence.inclusivelyBetween(0, 1) };
        };
        if([\measured, \proxy, \manual].includes(provenance).not) { valid = false };
        if(provenance == \measured) {
            valid = valid and: { BrahmaContracts.validMeasurement(map, strictness) and: {
                (confidence - map[\confidence]).abs < 1e-6
            } };
        };
        provenanceLog.add((time: Date.getDate,
            contract: if(contract.isNil) { "none" } { contract[\name] },
            valid: valid, provenance: provenance, confidence: confidence, missingKeys: missingKeys.asArray));
        if(provenanceLog.size > 1000) { provenanceLog.removeAt(0) };
        ^valid;
    }

    // --- Normalize a trait map using a named contract's ranges (delegates to BrahmaContracts) ---
    *normalize { |map, contractName|
        ^BrahmaContracts.normalize(map, this.contractFor(contractName));
    }

    // --- Load one contract JSON file into ~contracts ---
    *loadContract { |path|
        var contract = BrahmaContracts.load(path);
        if (contract.isNil) { ^nil };
        contracts[contract[\name].asSymbol] = contract;
        ("AdamKadmon: Loaded contract '" ++ contract[\name] ++ "' from " ++ path).postln;
        ^contract[\name].asSymbol;
    }

    // --- Load all substrate contracts from a directory (brahma/substrate/*.json) ---
    *loadSubstrateContracts { |dirPath|
        var loaded = List.new;
        if(PathName(dirPath).isFolder) {
            PathName(dirPath).files.do { |file|
                var name;
                if(file.extension == "json") {
                    name = this.loadContract(file.fullPath);
                    if(name.notNil) { loaded.add(name) };
                };
            };
        };
        ^loaded;
    }

    *contractNames {
        ^contracts.keys.asArray;
    }

    *provenanceLog {
        ^provenanceLog;
    }

    *clearProvenanceLog {
        provenanceLog = List.new;
    }

    *validateMeasurement { |map| ^BrahmaContracts.validMeasurement(map, strictness) }

    *checkPermission { |srcId, dstId, mode|
        // mode: read, write, infect
        // Simple mock permission logic
        // In full implementation, this would check the Registry contracts
        ^true;
    }

    *issueCapabilityToken { |entityId, capability|
        // Correlation identifier only; this is not a signed authorization token.
        ^[entityId, capability, Date.getDate.rawSeconds].asCompileString.hash;
    }
}
