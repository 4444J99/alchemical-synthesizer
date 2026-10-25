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
    classvar <provenanceLog = List.new; // list of {time, contract, valid, provenance, confidence, missingKeys}

    *initClass {
        contracts = Dictionary.new;
    }

    // --- Resolve a named contract (fallback to canonical_v1) ---
    *contractFor { |contractName|
        var contract = if (contractName.notNil) { contracts.at(contractName) } { nil };
        contract = if (contract.notNil) { contract } { ~defaultContract };
        ^contract;
    }

    // --- Default canonical schema (fallback when no named contract) ---
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

    // --- Validate a trait map against a named contract (manual provenance, full confidence) ---
    *validateTraitMap { |map, contractName|
        ^~validateCore(map, ~contractFor(contractName), \manual, 1.0);
    }

    // --- Validate with provenance: records where the trait map came from ---
    //   provenance: \measured (real DSP / FluCoMa), \proxy (derived estimate), \manual (human-set)
    //   confidence: 0..1, how much we trust this map
    *validateTraitMapWithProvenance { |map, contractName, provenance, confidence|
        provenance = if (provenance.notNil) { provenance } { \manual };
        confidence = if (confidence.notNil) { confidence.clip(0.0, 1.0) } { 1.0 };
        ^~validateCore(map, ~contractFor(contractName), provenance, confidence);
    }

    // --- Internal: shared validation core that delegates to BrahmaContracts and records provenance ---
    *~validateCore { |map, contract, provenance, confidence|
        var valid = true;
        var missingKeys = List.new;

        if (contract.isNil) {
            ("AdamKadmon: No contract available for validation").warn;
            valid = false;
        } {
            // Required-keys presence check (AdamKadmon-level, complementary to BrahmaContracts)
            var requiredKeys = contract[\requiredKeys] ?? [\spectral_profile, \temporal_topology, \modulation_graph, \performance_response];
            requiredKeys.do { |key|
                if (map.includesKey(key).not) {
                    ("AdamKadmon: Missing required trait dimension: " ++ key).warn;
                    valid = false;
                    missingKeys.add(key);
                };
            };

            // Delegate deep validation (types, ranges, requireMeasured, validMeasurement) to BrahmaContracts
            if (BrahmaContracts.validate(map, contract, ~strictness).not) {
                valid = false;
            };
        };

        // Strictness gate: if provenance claims measured but confidence < strictness, fail
        if (provenance == \measured and: { confidence < ~strictness }) {
            ("AdamKadmon: Measured confidence " ++ confidence ++ " below strictness " ++ ~strictness ++ " — rejecting").warn;
            valid = false;
        };

        // Record provenance entry
        ~provenanceLog.add(Dictionary.newFromPairs([
            #[\time -> Date.getDate,
              \contract -> (if (contract.isNil) { "none" } { contract[\name] ?? "canonical_v1" }),
              \valid -> valid,
              \provenance -> provenance.asSymbol,
              \confidence -> confidence,
              \missingKeys -> missingKeys]
        ]));
        // Cap log size to prevent unbounded growth
        if (~provenanceLog.size > 1000) { ~provenanceLog.removeFirst(~provenanceLog.size - 1000); };

        ^valid;
    }

    // --- Normalize a trait map using a named contract's ranges (delegates to BrahmaContracts) ---
    *normalize { |map, contractName|
        ^BrahmaContracts.normalize(map, ~contractFor(contractName));
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
        var dir = Folder(dirPath);
        var loaded = List.new;
        if (dir.notNil and: { dir.exists }) {
            dir.files.do { |f|
                if (f.endsWith(".json")) {
                    var name = ~loadContract(dirPath ++ "/" ++ f);
                    if (name.notNil) { loaded.add(name); };
                };
            };
        }
        ^loaded;
    }

    *contractNames {
        ^contracts.keys.asArray;
    }

    *provenanceLog {
        ^~provenanceLog;
    }

    *clearProvenanceLog {
        ~provenanceLog = List.new;
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
}