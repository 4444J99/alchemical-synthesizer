/*
  Phase 1: CHRONOS Clock Engine
  Polyrhythmic clock with per-track divisions, swing, transport
*/

(
// ==========================================
// TRANSPORT
// ==========================================
~CHRONOS[\play] = { |self|
    if(self[\playing].not) {
        self[\playing] = true;
        self[\clock] = TempoClock(self[\tempo] / 60);

        // Reset all track step counters
        self[\tracks].do({ |track|
            if(track.notNil) { track[\currentStep] = 0 };
        });

        // Start the master tick routine
        Tdef(\chronos_master, {
            var tickCount = 0;
            var ppqn = 96; // Pulses per quarter note (high resolution)

            loop {
                var tickDur = 60 / self[\tempo] / ppqn;

                // Process each active track
                self[\tracks].do({ |track, trackIdx|
                    if(track.notNil and: { track[\active] }) {
                        var trackPPQN, stepTrigger;

                        // Per-track clock division
                        // division: 1=whole, 2=half, 4=quarter, 8=8th, 16=16th, 32=32nd, 64=64th
                        trackPPQN = ppqn * 4 / track[\division]; // Ticks per step

                        // Check if this tick triggers a step for this track
                        if((tickCount % trackPPQN.round.asInteger) == 0) {
                            var step = track[\currentStep] % track[\numSteps];
                            var stepData = track[\pattern][step];
                            var shouldTrigger = false;
                            var swingOffset = 0;

                            // Apply swing to odd steps
                            if((step % 2) == 1) {
                                swingOffset = track[\swing].max(self[\globalSwing]);
                            };

                            // Evaluate step condition
                            shouldTrigger = ~CHRONOS_TRACKS.evaluateCondition(
                                stepData[\condition], step, track, self[\fillActive]);

                            // Probability gate
                            if(shouldTrigger and: { stepData[\probability] < 100 }) {
                                shouldTrigger = (stepData[\probability] / 100).coin;
                            };

                            // Mute/solo check
                            if(track[\muted]) { shouldTrigger = false };

                            if(shouldTrigger and: { stepData[\active] }) {
                                // Schedule trigger with micro-timing offset
                                var microOffset = stepData[\microTiming] * tickDur * trackPPQN / 100;
                                var swingDelay = swingOffset * tickDur * trackPPQN * 0.33;
                                var totalDelay = microOffset + swingDelay;

                                if(totalDelay > 0) {
                                    {
                                        totalDelay.wait;
                                        ~CHRONOS_TRACKS.triggerStep(trackIdx, step);
                                    }.fork(self[\clock]);
                                } {
                                    ~CHRONOS_TRACKS.triggerStep(trackIdx, step);
                                };

                                // Handle ratchets (retriggers within step)
                                if(stepData[\ratchet] > 1) {
                                    var ratchetInterval = tickDur * trackPPQN / stepData[\ratchet];
                                    (1..(stepData[\ratchet] - 1)).do({ |r|
                                        {
                                            (ratchetInterval * r).wait;
                                            ~CHRONOS_TRACKS.triggerStep(trackIdx, step);
                                        }.fork(self[\clock]);
                                    });
                                };
                            };

                            // Advance step counter
                            track[\currentStep] = track[\currentStep] + 1;
                        };
                    };
                });

                // Broadcast step position at reduced rate
                if((tickCount % (ppqn / 4)) == 0) { // Every 16th note
                    ~VISUAL_CORTEX.target.sendMsg(
                        "/chronos/tick", tickCount,
                        self[\tempo], self[\playing].asInteger);
                };

                tickCount = tickCount + 1;
                tickDur.wait;
            };
        }).play;

        // Broadcast transport state
        ~VISUAL_CORTEX.target.sendMsg("/chronos/transport", 1, self[\tempo]);
        "CHRONOS: Playing at % BPM".format(self[\tempo]).postln;
    };
};

~CHRONOS[\stop] = { |self|
    if(self[\playing]) {
        self[\playing] = false;
        Tdef(\chronos_master).stop;

        // Reset step counters
        self[\tracks].do({ |track|
            if(track.notNil) { track[\currentStep] = 0 };
        });

        ~VISUAL_CORTEX.target.sendMsg("/chronos/transport", 0, self[\tempo]);
        "CHRONOS: Stopped".postln;
    };
};

~CHRONOS[\setTempo] = { |self, bpm|
    self[\tempo] = bpm.clip(20, 300);
    if(self[\clock].notNil) {
        self[\clock].tempo = self[\tempo] / 60;
    };
    ~VISUAL_CORTEX.target.sendMsg("/chronos/transport",
        self[\playing].asInteger, self[\tempo]);
    "CHRONOS: Tempo set to % BPM".format(self[\tempo]).postln;
};

// ==========================================
// OSC TRANSPORT RESPONDERS
// ==========================================
OSCdef(\chronos_play, { ~CHRONOS.play }, "/chronos/transport/play");
OSCdef(\chronos_stop, { ~CHRONOS.stop }, "/chronos/transport/stop");
OSCdef(\chronos_tempo, { |msg| ~CHRONOS.setTempo(msg[1].asFloat) }, "/chronos/transport/tempo");
OSCdef(\chronos_fill_on, { ~CHRONOS[\fillActive] = true }, "/chronos/fill/on");
OSCdef(\chronos_fill_off, { ~CHRONOS[\fillActive] = false }, "/chronos/fill/off");

// Scene OSC
OSCdef(\chronos_scene_save, { |msg| ~CHRONOS.saveScene(msg[1].asInteger) }, "/chronos/scene/save");
OSCdef(\chronos_scene_load, { |msg| ~CHRONOS.loadScene(msg[1].asInteger) }, "/chronos/scene/load");
OSCdef(\chronos_scene_morph, { |msg| ~CHRONOS.morphScenes(msg[1].asFloat) }, "/chronos/scene/morph");
OSCdef(\chronos_scene_morph_src, { |msg| ~CHRONOS[\morphSourceScene] = msg[1].asInteger.clip(0,7) }, "/chronos/scene/morph/src");
OSCdef(\chronos_scene_morph_dst, { |msg| ~CHRONOS[\morphTargetScene] = msg[1].asInteger.clip(0,7) }, "/chronos/scene/morph/dst");

// Undo/Redo
OSCdef(\chronos_undo, { ~CHRONOS.undo }, "/chronos/undo");
OSCdef(\chronos_redo, { ~CHRONOS.redo }, "/chronos/redo");

// Song mode
OSCdef(\chronos_song_toggle, { |msg|
    ~CHRONOS[\songMode] = msg[1].asInteger > 0;
    "CHRONOS: Song mode %".format(if(~CHRONOS[\songMode], "ON", "OFF")).postln;
}, "/chronos/song/toggle");

OSCdef(\chronos_song_add, { |msg|
    ~CHRONOS.addSongEntry(msg[1].asInteger, msg[2].asInteger, msg[3]);
}, "/chronos/song/add");

OSCdef(\chronos_song_clear, { ~CHRONOS.clearSong }, "/chronos/song/clear");

// ==========================================
// GOLEM LEGACY ALIASES
// Maintain backward compatibility with Golem OSC
// ==========================================
OSCdef(\golem_play_alias, { ~CHRONOS.play }, "/golem/transport/play");
OSCdef(\golem_stop_alias, { ~CHRONOS.stop }, "/golem/transport/stop");
OSCdef(\golem_tempo_alias, { |msg| ~CHRONOS.setTempo(msg[1].asFloat) }, "/golem/transport/tempo");

"--- BRAHMA: CHRONOS Clock Engine Online ---".postln;
)
