(
var check, measured, absorbed, transformed, state, stats, proxyContract, proxy, manual, missing;
check = { |condition, label| if(condition.not) { Error("FAIL: " ++ label).throw }; ("PASS: " ++ label).postln };
try {
    (thisProcess.nowExecutingPath.dirname.dirname +/+ "11_metrics.scd").load;
    check.value(AdamKadmon.contractFor(\sound)[\requireMeasured] == true, "JSON boolean flag is decoded");
    check.value(AdamKadmon.contractFor(\sound)[\ranges][\spectral_profile][\min].isNumber, "JSON numeric ranges are decoded");
    check.value(AdamKadmon.loadSubstrateContracts(thisProcess.nowExecutingPath.dirname.dirname.dirname +/+ "substrate").size == 4, "substrate directory loader uses native paths");
    AdamKadmon.clearProvenanceLog;
    measured = ~metric_collector.attachMeasurements((spectral_profile: (centroid: 0.2), temporal_topology: (attack: 0.3), modulation_graph: (depth: 0.4), performance_response: (velocity: 0.5)), 0.9, 2.0, 0.95);
    check.value(AdamKadmon.validateTraitMapWithProvenance(measured, \sound, \measured, 0.95), "measured provenance validates real evidence");
    check.value(AdamKadmon.provenanceLog.last[\valid] == true, "provenance log records validation");
    check.value(AdamKadmon.validateTraitMapWithProvenance(measured, \sound, \measured, 0.1).not, "low provenance confidence rejected");
    check.value(TransmutationEngine.operatorsList.includes(\default), "transmutation class initializes its operators");
    check.value(TransmutationEngine.absorb("invalid", \sound).isNil, "non-map donor fails cleanly");
    absorbed = TransmutationEngine.absorb(measured, \sound);
    check.value(absorbed.notNil, "transmutation resolves substrate aliases");
    check.value(TransmutationEngine.transmute(absorbed, \sound, \sound, \unknown).isNil,
        "unknown operator cannot silently claim a successful identity transform");
    transformed = TransmutationEngine.transmute(absorbed, \sound, \sound, \spectralToHarmonic);
    check.value(transformed.isNil, "transformed output cannot reuse donor measurement proof");
    check.value((TransmutationEngine.mapDimension((centroid: 0.2), { |value| value * 0.8 + 0.2 })[\centroid] - 0.36).abs < 1e-6, "operators handle nested measured dimensions");
    check.value(TransmutationEngine.transmute(absorbed, \sound, \sound, \default).notNil, "unchanged identity retains valid measurement proof");
    // Isolate a real transformation into an explicitly unmeasured target.
    // Shipped non-audio schemas have different shapes and still require evidence.
    proxyContract = AdamKadmon.contractFor(\sound).deepCopy;
    proxyContract[\name] = \proxy_target_v1; proxyContract[\requireMeasured] = false;
    AdamKadmon.contracts[\proxy_target_v1] = proxyContract;
    proxy = TransmutationEngine.transmute(absorbed, \sound, \proxy_target, \spectralToHarmonic);
    check.value(proxy.notNil, "actual transform succeeds for an explicitly unmeasured target");
    check.value((proxy[\spectral_profile][\centroid] - 0.36).abs < 1e-6,
        "successful proxy output contains the transformed trait value");
    check.value(proxy[\provenance] == \proxy and: {
        proxy[\confidence].isNil and: { proxy[\measurements].isNil }
    }, "proxy transformation strips inherited evidence without fabricating confidence");
    check.value(AdamKadmon.provenanceLog.last[\confidence].isNil,
        "proxy validation log records unknown confidence as nil");
    check.value(AdamKadmon.validateMeasurement(proxy, \proxy_target).not,
        "successful structural transformation does not claim measured evidence");
    check.value(TransmutationEngine.absorb(proxy, \proxy_target).notNil,
        "unmeasured donor can be absorbed where its contract permits it");
    check.value(AdamKadmon.provenanceLog.last[\confidence].isNil,
        "absorption does not replace unknown confidence with one");
    manual = measured.deepCopy;
    [\confidence, \provenance, \measurements].do { |key| manual.removeAt(key) };
    check.value(AdamKadmon.validateTraitMap(manual), "manual canonical traits remain valid without evidence");
    check.value(AdamKadmon.provenanceLog.last[\confidence].isNil,
        "basic validation does not invent manual confidence");
    check.value(AdamKadmon.validateTraitMapWithProvenance(manual, nil, \proxy),
        "explicit proxy provenance can retain unknown confidence");
    check.value(AdamKadmon.provenanceLog.last[\confidence].isNil,
        "explicit provenance does not invent confidence");
    missing = measured.deepCopy; missing.removeAt(\confidence);
    check.value(AdamKadmon.validateTraitMapWithProvenance(missing, \sound, \measured).not,
        "measured provenance requires actual map confidence");
    check.value(AdamKadmon.validateTraitMapWithProvenance(measured, \sound, \measured),
        "omitted measured argument derives existing confidence only");
    check.value(AdamKadmon.provenanceLog.last[\confidence] == 0.95,
        "measured provenance log preserves the supplied map confidence");
    check.value(AdamKadmon.validateTraitMapWithProvenance(manual, nil, \proxy, inf).not,
        "nonfinite proxy confidence remains invalid");
    check.value(AdamKadmon.validateTraitMapWithProvenance(measured, \sound, \measured, 0.0/0.0).not,
        "nonfinite measured confidence remains invalid");
    TransmutationEngine.registerOperator(\default, { |map|
        map[\spectral_profile][\centroid] = 0.7; map;
    });
    check.value(TransmutationEngine.transmute(absorbed, \sound, \sound, \default).isNil, "custom default cannot retain stale measurement proof");
    check.value(absorbed[\spectral_profile][\centroid] == 0.2, "custom operators cannot mutate donor proof");
    BridgeRouter.registerPeer("test.local", 57230, 0);
    BridgeRouter.peerHeartbeat("test.local", Date.getDate.rawSeconds * 1000);
    stats = BridgeRouter.peerStatus;
    check.value(stats.any { |peer| peer[\host] == "test.local" and: { peer[\healthy] == true } }, "peer heartbeat and status use class state");
    state = (active_links: List.new);
    BridgeRouter.emitLinkSet(state, 1, 2, \read, -1);
    BridgeRouter.tick(state);
    check.value(state[\active_links].isEmpty and: { BridgeRouter.healthyPaths(1, 2).isEmpty }, "bridge tick expires links in both registries");
    "BRAHMA_TEST_PASS".postln; 0.exit;
} { |err| err.reportError; 1.exit };
)
