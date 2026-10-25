(
var check, measured, absorbed, transformed, state, stats;
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
    absorbed = TransmutationEngine.absorb(measured, \sound);
    check.value(absorbed.notNil, "transmutation resolves substrate aliases");
    transformed = TransmutationEngine.transmute(absorbed, \sound, \sound, \spectralToHarmonic);
    check.value(transformed.isNil, "transformed output cannot reuse donor measurement proof");
    check.value((TransmutationEngine.mapDimension((centroid: 0.2), { |value| value * 0.8 + 0.2 })[\centroid] - 0.36).abs < 1e-6, "operators handle nested measured dimensions");
    check.value(TransmutationEngine.transmute(absorbed, \sound, \sound, \default).notNil, "unchanged identity retains valid measurement proof");
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
