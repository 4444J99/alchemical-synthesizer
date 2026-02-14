/*
  Phase 14: The Visual Cortex Integration
  Broadcasting Trait Maps to the Web
*/

(
~VISUAL_CORTEX = (
    target: NetAddr("127.0.0.1", 57122), // Node.js server

    // Broadcast an update for an entity
    broadcastUpdate: { |self, entityId, type, coherence, entropy|
        self.target.sendMsg("/brahma/organism/update", entityId, type, coherence, entropy);
    },

    // Broadcast Golem-specific state at 10Hz
    broadcastGolem: { |self|
        if(~GOLEM.notNil and: { ~GOLEM_SEQ.notNil }) {
            // Organism-level update
            var coherence = ~METRIC_COLLECTOR.measureCoherence(nil);
            var entropy = ~METRIC_COLLECTOR.measureEntropy(nil);
            self.target.sendMsg("/golem/organism/update",
                ~GOLEM[\entityId], "Golem", coherence, entropy);

            // Sequencer state
            self.target.sendMsg("/golem/seq/state",
                ~GOLEM_SEQ[\playing].asInteger,
                ~GOLEM_SEQ[\tempo],
                ~GOLEM_SEQ[\currentStep]);

            // Per-track state
            ~GOLEM_SEQ[\tracks].do({ |track, i|
                self.target.sendMsg("/golem/track/state",
                    i,
                    track[\muted].asInteger,
                    track[\solo].asInteger);

                // FX state
                self.target.sendMsg("/golem/fx/state",
                    i,
                    track[\fx][\reverbMix],
                    track[\fx][\delayMix],
                    track[\fx][\bitcrush],
                    track[\fx][\drive]);

                // Engine state
                self.target.sendMsg("/golem/engine/state",
                    i,
                    track[\synthDef].asString,
                    track[\synthArgs][\freq] ? 150,
                    track[\synthArgs][\cutoff] ? 2000);

                // LFO values
                track[\lfos].do({ |lfo, li|
                    if(lfo[\bus].notNil) {
                        self.target.sendMsg("/golem/lfo/value",
                            i, li, lfo[\bus].getSynchronous);
                    };
                });
            });
        };
    },

    // Auto-Broadcast Loop
    startStream: { |self|
        Tdef(\viz_stream, {
            loop {
                // Existing organism broadcasts
                self.broadcastUpdate(1001, "Relinquished", rrand(0.4, 0.9), rrand(1.0, 5.0));
                self.broadcastUpdate(1002, "Proteus", rrand(0.8, 1.0), rrand(0.1, 2.0));

                // Golem broadcast
                self.broadcastGolem;

                0.1.wait; // 10Hz update rate
            }
        }).play;
        "--- VISUAL CORTEX STREAM ACTIVE ---".postln;
    },

    stopStream: {
        Tdef(\viz_stream).stop;
        "--- VISUAL CORTEX STREAM STOPPED ---".postln;
    }
);

// Start by default for demo purposes
~VISUAL_CORTEX.startStream;
)
