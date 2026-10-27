/*
  Phase 10: Validation & Regression
  Measurement Harness
*/

(
~measure = (
    // Stimuli Generation
    playSineSweep: { |self, bus, start=20, end=20000, dur=5|
        { Sweep.ar(Impulse.ar(1/dur), end-start) + start }.play(s, bus);
    },

    // Capture & Metric Calculation
    analyzeEntity: { |self, entityId, registry|
        var traits = registry.getTraits(entityId);
        "Analysis for %: %".format(entityId, traits).postln;
    },

    // Reference Vectors (Make NoiseMATHS approx)
    refMATHS: (
        spectral_profile: (centroid: 0.2, flatness: 0.1),
        temporal_topology: (attack: 0.1, decay: 0.5, slew: 0.8),
        modulation_graph: (type: \function_generator)
    ),

    // ==========================================
    // GOLEM ANALYSIS
    // ==========================================
    // Per-track audition and reference report. This path does not capture
    // audio; use analyzeFile or the asynchronous measureBuffer for metrics.
    analyzeGolem: { |self|
        "--- GOLEM: Per-Track Spectral Analysis ---".postln;
        {
            var refVectors = (
                kick808: (centroid: 0.05, flatness: 0.1, bandwidth: 0.2),
                snare: (centroid: 0.4, flatness: 0.6, bandwidth: 0.5),
                clap: (centroid: 0.45, flatness: 0.8, bandwidth: 0.6),
                hihatClosed: (centroid: 0.8, flatness: 0.9, bandwidth: 0.3),
                hihatOpen: (centroid: 0.75, flatness: 0.85, bandwidth: 0.5),
                tom: (centroid: 0.15, flatness: 0.15, bandwidth: 0.25),
                rim: (centroid: 0.55, flatness: 0.3, bandwidth: 0.2),
                fmBell: (centroid: 0.6, flatness: 0.2, bandwidth: 0.4)
            );

            ~golem_seq.tracks.do({ |track, i|
                var name = track[\name].asSymbol;
                var ref = refVectors[name];

                // Audition the voice. No analysis buffer is allocated here.
                if(track[\audioBus].notNil) {
                    var bus, syn;
                    bus = track[\audioBus];

                    "  Track %: % (%)".format(i, name, track[\synthDef]).postln;

                    syn = Synth(track[\synthDef],
                        [\outBus, bus.index, \velocity, 0.8, \gate, 1]
                        ++ track[\synthArgs].asPairs,
                        target: ~sc_grp[\te]
                    );

                    0.3.wait;

                    "    Spectral measurement unavailable: this audition has no captured audio.".postln;

                    if(ref.notNil) {
                        "    Reference centroid (normalized): %".format(ref[\centroid]).postln;
                    };

                    0.3.wait;
                } {
                    "  Track %: % — no bus allocated (skipping)".format(i, name).postln;
                };
            });

            "--- GOLEM: Analysis Complete ---".postln;
        }.fork;
    },

    // Quick Golem health check
    golemHealthCheck: { |self|
        var ok, busCount;
        "--- GOLEM HEALTH CHECK ---".postln;
        ok = true;

        // Check registration
        if(~brahma_registry.entities[~golem[\entityId]].notNil) {
            "  Registry: OK (entity %)".format(~golem[\entityId]).postln;
        } {
            "  Registry: FAIL — Golem not registered".postln;
            ok = false;
        };

        // Check bus allocation
        busCount = ~golem_seq.tracks.count({ |t| t[\audioBus].notNil });
        "  Buses: % of 8 tracks allocated".format(busCount).postln;
        if(busCount < 8) { ok = false };

        // Check equip state
        "  Equip state: %".format(~golem[\equipState]).postln;

        // Check sequencer
        "  Sequencer: % tracks, tempo % BPM, playing: %".format(
            ~golem_seq[\numTracks], ~golem_seq[\tempo], ~golem_seq[\playing]
        ).postln;

        if(ok) {
            "  OVERALL: HEALTHY".postln;
        } {
            "  OVERALL: DEGRADED".postln;
        };
    }
);

"--- BRAHMA: Measurement Harness Ready ---".postln;
)
