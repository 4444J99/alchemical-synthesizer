/*
  Phase 14: The Visual Cortex Integration
  Broadcasting Trait Maps to the Web
*/

(
~visual_cortex = (
    target: NetAddr("127.0.0.1", 57122), // Node.js server
    demoMode: false,

    // Broadcast an update for an entity
    broadcastUpdate: { |self, entityId, type, coherence, entropy|
        self.target.sendMsg("/brahma/organism/update", entityId, type, coherence, entropy);
    },

    // Broadcast Golem-specific state at 10Hz
    broadcastGolem: { |self|
        if(~golem.notNil and: { ~golem_seq.notNil }) {
            // This controller has no captured audio buffer. Do not turn
            // absent measurements into numeric organism telemetry.
            self.target.sendMsg("/brahma/organism/measurement/status",
                ~golem[\entityId], "Golem", "unavailable", "no_audio_capture");

            // Sequencer state
            self.target.sendMsg("/golem/seq/state",
                ~golem_seq[\playing].asInteger,
                ~golem_seq[\tempo],
                ~golem_seq[\currentStep]);

            // Per-track state
            ~golem_seq[\tracks].do({ |track, i|
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
                // Synthetic data is opt-in and labeled in the organism type.
                if(self.demoMode) {
                    self.broadcastUpdate(1001, "DEMO Relinquished", rrand(0.4, 0.9), rrand(1.0, 5.0));
                    self.broadcastUpdate(1002, "DEMO Proteus", rrand(0.8, 1.0), rrand(0.1, 2.0));
                };

                // Golem broadcast
                self.broadcastGolem;

                0.1.wait; // 10Hz update rate
            }
        }).play;
        if(self.demoMode) {
            "--- VISUAL CORTEX STREAM ACTIVE (DEMO: synthetic organism metrics) ---".postln;
        } {
            "--- VISUAL CORTEX STREAM ACTIVE (organism measurements unavailable: no live capture) ---".postln;
        };
    },

    stopStream: {
        Tdef(\viz_stream).stop;
        "--- VISUAL CORTEX STREAM STOPPED ---".postln;
    }
);

// Stream transport/track state. Set demoMode=true explicitly for synthetic visuals.
~visual_cortex.startStream;
)
