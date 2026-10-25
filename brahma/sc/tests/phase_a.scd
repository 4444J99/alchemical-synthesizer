(
var check, source, changed, noise, traits, idea, fsap, registry, stereo, mixed;
check = { |condition, label|
    if(condition.not) { Error("FAIL: " ++ label).throw; };
    ("PASS: " ++ label).postln;
};
try {
    source = Signal.fill(4096, { |i| sin(2pi * 64 * i / 4096) });
    changed = Signal.fill(4096, { |i| sin(2pi * (i.squared / 4096)) });
    thisThread.randSeed = 741;
    noise = Signal.fill(4096, { 1.0.rand2 });
    (thisProcess.nowExecutingPath.dirname.dirname +/+ "11_metrics.scd").load;
    check.value(~metric_collector.notNil, "metrics file compiles");
    check.value(~metric_collector.measureCoherence(source) > 0.95, "steady spectral coherence");
    check.value(~metric_collector.measureEntropy(noise) > (~metric_collector.measureEntropy(source) + 2), "noise has higher spectral entropy than tone");
    check.value(~metric_collector.measureFidelity(source, source) > 0.999, "identical signal fidelity");
    check.value(~metric_collector.measureFidelity(source, source.neg) < 0.01, "inverted signal is not faithful reconstruction");
    check.value(~metric_collector.measureCoherence(source) > ~metric_collector.measureCoherence(changed), "changing spectrum lowers coherence");
    stereo = source.collect { |v| [v, v] }.flat;
    mixed = source.collect { |v, i| [v, noise[i]] }.flat;
    check.value(BrahmaMetrics.fidelity(stereo, mixed, 2).inclusivelyBetween(0.45, 0.55), "multichannel fidelity averages channel correlations");
    check.value(try { BrahmaMetrics.entropy([0.0/0.0]); false } { true }, "nonfinite samples are rejected");
    check.value(~metric_collector.measureEntropy([]) == 0, "empty signal entropy");
    traits = (spectral_profile: (centroid: 0.2), temporal_topology: (attack: 0.1), modulation_graph: (depth: 0.2), performance_response: (velocity: 0.8));
    check.value(~metric_collector.attachMeasurements(traits, 0.9, 2.0, 0.95)[\provenance] == \measured, "measurement provenance is explicit");
    check.value(AdamKadmon.validateMeasurement(~metric_collector.attachMeasurements(traits, 0.9, 2.0, 0.2)).not, "measured poor reconstruction fails confidence gate");
    check.value(AdamKadmon.validateTraitMap(traits), "canonical nested traits validate");
    check.value(AdamKadmon.validateTraitMap(traits, \unknown).not, "unknown contract fails closed");
    check.value(AdamKadmon.validateTraitMap(traits.copy.put(\confidence, 0.2)).not, "low confidence fails validation");
    check.value(AdamKadmon.loadContract(thisProcess.nowExecutingPath.dirname.dirname.dirname +/+ "substrate/idea.json").notNil, "JSON substrate contract loads");
    idea = (abstraction: 0.2, development: 0.3, implication: 0.4, provocation: 0.5, confidence: 0.95, provenance: \manual);
    check.value(AdamKadmon.validateTraitMap(idea.copy.put(\abstraction, \garbage), \idea_v1).not, "numeric substrate axes reject strings");
    check.value(AdamKadmon.validateTraitMap(traits.copy.put(\spectral_profile, (centroid: \garbage))).not, "numeric audio traits reject strings");
    check.value(AdamKadmon.validateTraitMap(idea.copy.put(\abstraction, (value: 0.2)), \idea_v1).not, "scalar substrate axes reject dictionaries");
    check.value(AdamKadmon.validateTraitMap(idea, \idea_v1), "non-audio substrate validates");
    check.value(AdamKadmon.normalize(traits.copy.put(\spectral_profile, (centroid: 2.0)))[\spectral_profile][\centroid] == 1, "nested normalization preserves dimensions");
    fsap = FSAP.new;
    registry = (getTraits: { |self, id| traits.copy.put(\confidence, 0.2) });
    fsap.observe(1, registry); fsap.absorb; fsap.integrate; fsap.accumulate;
    check.value(fsap.stack.isEmpty, "FSAP blocks low-confidence accumulation");
    check.value(AdamKadmon.validateMeasurement((confidence: 0.95, provenance: \measured)).not, "provenance requires actual metric evidence");
    fsap = FSAP.new;
    registry = (getTraits: { |self, id| ~metric_collector.attachMeasurements(traits, 0.9, 2.0, 0.95) });
    fsap.observe(1, registry); fsap.absorb; fsap.integrate; fsap.accumulate;
    check.value(fsap.stack.size == 1, "FSAP accepts measured high-confidence traits");
    "BRAHMA_TEST_PASS".postln; 0.exit;
} { |err| err.reportError; 1.exit; };
)
