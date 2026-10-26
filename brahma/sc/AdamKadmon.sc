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
      (provenance: \measured / \proxy / \manual; confidence: 0..1 or nil when unknown).
  - normalize(map, contractName) normalizes a trait map using a named contract's ranges.
  - contractNames() returns the list of loaded contract names.
  - provenanceLog returns the full validation provenance log.
*/

AdamKadmon {
    classvar <ontologyProfile = 'canonical_v1';
    classvar <strictness = 0.85;        // default confidence threshold; schema strictness is metadata
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
            ranges: (spectral_profile: (min: 0.0, max: 1.0)), strictness: strictness);
    }

    // --- Validate a trait map using its declared evidence, without inventing confidence ---
    *validateTraitMap { |map, contractName|
        ^this.validateTraitMapWithProvenance(map, contractName);
    }

    // --- Validate with provenance: records where the trait map came from ---
    //   provenance: \measured (real DSP / FluCoMa), \proxy (derived estimate), \manual (human-set)
    //   confidence: supplied 0..1 or nil (unknown) for manual/proxy traits.
    // Omitted arguments may use fields already in the map, never a fabricated
    // default. Measured provenance requires real confidence and metric evidence.
    *validateTraitMapWithProvenance { |map, contractName, provenance, confidence|
        if(map.isKindOf(Dictionary)) {
            provenance = provenance ? map[\provenance];
            confidence = confidence ? map[\confidence];
        };
        provenance = provenance ? \manual;
        ^this.validateCore(map, this.contractFor(contractName), provenance, confidence);
    }

    // --- Internal: shared validation core that delegates to BrahmaContracts and records provenance ---
    *validateCore { |map, contract, provenance, confidence|
        var valid, missingKeys = List.new;
        valid = BrahmaContracts.validate(map, contract, strictness);
        if(map.isKindOf(Dictionary) and: { contract.notNil }) {
            contract[\requiredKeys].do { |key| if(map.includesKey(key).not) { missingKeys.add(key) } };
        };
        if(confidence.notNil) {
            valid = valid and: { BrahmaContracts.finiteNumber(confidence) and: {
                confidence.inclusivelyBetween(0, 1)
            } };
        };
        if([\measured, \proxy, \manual].includes(provenance).not) { valid = false };
        if(provenance == \measured) {
            valid = valid and: { BrahmaContracts.finiteNumber(confidence) and: {
                BrahmaContracts.validMeasurement(map,
                    contract[\provenance_min_confidence] ? strictness) and: {
                    (confidence - map[\confidence]).abs < 1e-6
                }
            } };
        };
        provenanceLog.add((time: Date.getDate,
            contract: if(contract.isNil) { "none" } { contract[\name] },
            valid: valid, provenance: provenance, confidence: confidence,
            confidenceAvailable: BrahmaContracts.finiteNumber(confidence), missingKeys: missingKeys.asArray));
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
        ^([\canonical_v1] ++ contracts.keys.asArray).sort;
    }

    *provenanceLog {
        ^provenanceLog;
    }

    *clearProvenanceLog {
        provenanceLog = List.new;
    }

    *validateMeasurement { |map, contractName|
        var contract = this.contractFor(contractName);
        if(contract.isNil) { ^false };
        ^BrahmaContracts.validMeasurement(map, contract[\provenance_min_confidence] ? strictness);
    }

    *checkPermission { |srcId, dstId, mode|
        // mode: read, write, infect
        // Existing placeholder, not an authentication/authorization boundary.
        ^true;
    }

    *issueCapabilityToken { |entityId, capability|
        // A hash is not a signed capability. No signing backend is configured.
        ^Error("AdamKadmon capability signing is unavailable").throw;
    }
}
