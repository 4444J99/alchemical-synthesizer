(
var work = "BRAHMA_TEST_TMP".getenv;
var failures = 0, check, write, original, bad, normalized, name, count, fsap, registry;
check = { |condition, label|
    if(condition == true) { ("PASS " ++ label).postln } {
        failures = failures + 1; ("FAIL " ++ label).postln;
    };
};
write = { |name, text|
    var path = work +/+ name, file = File(path, "w");
    file.write(text); file.close; path
};
original = (
    spectral_profile: (centroid: 0.5, flatness: 0.2),
    temporal_topology: (attack: 0.01),
    modulation_graph: (type: \percussive, sources: 24),
    performance_response: (velocity: 0.8)
);
check.(AdamKadmon.validateTraitMap(original), "canonical traits accept existing categorical metadata");
[\spectral_profile, \temporal_topology, \modulation_graph, \performance_response].do { |dimension|
    bad = original.deepCopy; bad[dimension] = Dictionary.new;
    check.(AdamKadmon.validateTraitMap(bad).not,
        "canonical required dimension rejects empty object: " ++ dimension);
    check.(AdamKadmon.normalize(bad).isNil,
        "normalization rejects empty required dimension: " ++ dimension);
    [inf, inf.neg, 0.0/0.0, \garbage].do { |value, index|
        bad = original.deepCopy; bad[dimension] = (value: value);
        check.(AdamKadmon.validateTraitMap(bad).not,
            "canonical required dimension rejects invalid leaf: " ++ dimension ++ " case " ++ index);
        check.(AdamKadmon.normalize(bad).isNil,
            "normalization rejects invalid required leaf: " ++ dimension ++ " case " ++ index);
    };
};
check.(AdamKadmon.normalize(original)[\modulation_graph][\sources] == 24,
    "structural validation preserves unbounded finite metadata counts");
check.(AdamKadmon.validateTraitMap(nil).not, "nil traits fail cleanly");
check.(AdamKadmon.validateTraitMap((spectral_profile: (centroid: 0.5))).not,
    "missing canonical dimensions fail");
bad = original.deepCopy; bad[\spectral_profile] = "invalid";
check.(AdamKadmon.validateTraitMap(bad).not, "canonical dimension types are checked");
bad = original.deepCopy; bad[\spectral_profile][\centroid] = 2;
check.(AdamKadmon.validateTraitMap(bad).not, "canonical spectral range is enforced");
normalized = AdamKadmon.normalize(bad);
check.(normalized[\spectral_profile][\centroid] == 1, "canonical normalization clamps numeric values");
check.(bad[\spectral_profile][\centroid] == 2, "normalization preserves donor map");
check.(normalized[\modulation_graph][\type] == \percussive, "normalization preserves categorical metadata");
name = AdamKadmon.loadContract(write.("contract.json",
    "{\"name\":\"test_contract\",\"requiredKeys\":[\"spectral_profile\",\"level\"],\"strictness\":0.9,\"ranges\":{\"spectral_profile.centroid\":{\"min\":0.2,\"max\":0.8},\"level\":{\"min\":-6,\"max\":6}}}"));
check.(name == \test_contract, "JSON contract loads using the stock SC decoder");
check.(AdamKadmon.contractNames.includes(\test_contract), "named contract is discoverable");
check.(AdamKadmon.contracts[\test_contract][\strictness] == 0.9,
    "string-valued JSON numeric metadata is validated and converted");
check.(AdamKadmon.validateTraitMap((spectral_profile: (centroid: 0.5), level: 3), name),
    "named scalar and dotted ranges validate");
check.(AdamKadmon.validateTraitMap((spectral_profile: (centroid: 0.9), level: 3), name).not,
    "dotted range violations fail");
check.(AdamKadmon.validateTraitMap((spectral_profile: (centroid: 0.5), level: "loud"), name).not,
    "nonnumeric ranged traits fail");
check.(AdamKadmon.validateTraitMap((spectral_profile: (centroid: 0.5)), name).not,
    "named required keys are enforced");
bad = (spectral_profile: (centroid: -1), level: 10);
normalized = AdamKadmon.normalize(bad, name);
check.(normalized[\spectral_profile][\centroid] == 0.2 and: { normalized[\level] == 6 },
    "named normalization uses contract ranges");
check.(bad[\level] == 10, "named normalization preserves donor");
check.(AdamKadmon.validateTraitMap(original, \missing_contract).not,
    "unknown contract cannot silently fall back");
check.(AdamKadmon.normalize(original, \missing_contract).isNil, "unknown normalization fails cleanly");
name = AdamKadmon.loadContract(write.("conflicting.json",
    "{\"name\":\"conflicting\",\"requiredKeys\":[\"spectral_profile\"],\"ranges\":{\"spectral_profile\":{\"min\":0,\"max\":1},\"spectral_profile.centroid\":{\"min\":2,\"max\":3}}}"));
check.(AdamKadmon.normalize((spectral_profile: (centroid: 0.5)), name).isNil,
    "normalization never returns a map that violates overlapping ranges");
count = AdamKadmon.contractNames.size;
check.(AdamKadmon.loadContract(work +/+ "absent.json").isNil, "missing contract file fails cleanly");
check.(AdamKadmon.loadContract(write.("bad.json", "{")).isNil, "malformed contract fails cleanly");
check.(AdamKadmon.loadContract(write.("bad-number.json",
    "{\"name\":\"bad\",\"requiredKeys\":[\"level\"],\"ranges\":{\"level\":{\"min\":\"oops\",\"max\":1}}}")).isNil,
    "invalid numeric schema is not coerced to zero");
check.(AdamKadmon.loadContract(write.("bad-range.json",
    "{\"name\":\"bad\",\"requiredKeys\":[\"level\"],\"ranges\":{\"level\":{\"min\":2,\"max\":1}}}")).isNil,
    "reversed schema ranges are rejected");
check.(AdamKadmon.contractNames.size == count, "failed loads do not mutate contract registry");
check.(AdamKadmon.loadContract(write.("bad-shape.json",
    "{\"name\":\"bad\",\"requiredKeys\":[\"level\"],\"ranges\":{\"level\":4}}")).isNil,
    "malformed range shape fails without throwing");
check.(try { AdamKadmon.issueCapabilityToken(\entity, \write); false } { true },
    "unsigned hashes cannot masquerade as AdamKadmon capabilities");
check.(try { BridgeRouter.issueCapabilityToken(\entity, \write); false } { true },
    "unsigned hashes cannot masquerade as bridge capabilities");
name = AdamKadmon.loadContract(write.("typed-ranges.json",
    "{\"name\":\"typed_ranges\",\"requiredKeys\":[\"spectral_profile\"],\"ranges\":{\"optional\":{\"min\":0,\"max\":1,\"type\":\"number\"},\"spectral_profile.centroid\":{\"min\":0,\"max\":1,\"type\":\"number\"}}}"));
bad = (spectral_profile: (centroid: 0.5), optional: (value: 0.5));
check.(AdamKadmon.validateTraitMap(bad, name).not, "optional scalar range rejects a dictionary");
check.(AdamKadmon.normalize(bad, name).isNil, "normalization enforces optional range type");
bad = (spectral_profile: (centroid: (value: 0.5)));
check.(AdamKadmon.validateTraitMap(bad, name).not, "dotted scalar range rejects a dictionary");
check.(AdamKadmon.normalize(bad, name).isNil, "normalization enforces dotted range type");
name = AdamKadmon.loadContract(write.("threshold.json",
    "{\"name\":\"threshold\",\"requiredKeys\":[\"level\"],\"ranges\":{\"level\":{\"min\":0,\"max\":1}},\"provenance_min_confidence\":0.5,\"requireMeasured\":true}"));
bad = (level: 0.5, confidence: 0.7, provenance: \measured,
    measurements: (coherence: 0.9, entropy: 2.0, fidelity: 0.7));
check.(AdamKadmon.validateTraitMap(bad, name), "selected confidence threshold validates schema");
check.(AdamKadmon.validateTraitMapWithProvenance(bad, name, \measured, 0.7),
    "provenance uses the same selected confidence threshold");
check.(AdamKadmon.validateMeasurement(bad, name), "measurement admission honors selected contract");
check.(AdamKadmon.validateMeasurement(bad, \unknown_contract).not,
    "unknown measurement contract cannot silently use default policy");
fsap = FSAP.new; registry = (getTraits: { |self, id| bad });
fsap.observe(1, registry); fsap.absorb; fsap.integrate(contractName: name); fsap.accumulate;
check.(fsap.stack.size == 1, "FSAP forwards the selected contract's measurement threshold");
if(failures == 0) { "DSP_PASS contracts".postln; 0.exit } { 1.exit };
)
