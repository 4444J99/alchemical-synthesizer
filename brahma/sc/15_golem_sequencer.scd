/*
  Phase 15: Golem Sequencer Engine
  Step sequencer, LFO engine, modulation matrix
*/

(
// ==========================================
// LFO SynthDef (control-rate, 3 per track = 24 total)
// ==========================================
SynthDef(\golem_lfo, {
    |outBus=0, rate=1, shape=0, phase=0, gate=1|

    var sig;

    // 5 shapes: 0=sine, 1=square, 2=saw, 3=tri, 4=random
    sig = Select.kr(shape.clip(0, 4), [
        SinOsc.kr(rate, phase),
        LFPulse.kr(rate, phase).bipolar,
        LFSaw.kr(rate, phase),
        LFTri.kr(rate, phase),
        LFNoise1.kr(rate)
    ]);

    Out.kr(outBus, sig);
}).add;

// ==========================================
// SEQUENCER ENGINE (language-side)
// ==========================================
~golem_seq = (

    // State
    playing: false,
    tempo: 120,
    currentStep: 0,
    numTracks: 8,
    clock: nil,

    // Track data: 8 tracks, each with pattern, settings, state
    tracks: Array.fill(8, { |i|
        (
            id: i,
            name: "Track " ++ (i + 1),
            steps: 16,
            swing: 0,  // 0..1, applied as offset on odd steps
            pattern: Array.fill(16, {
                (active: false, velocity: 0.8, pLocks: nil)
            }),
            automation: Dictionary.new,  // paramName -> Array[16] of values

            // Engine state (which SynthDef + args)
            synthDef: \drum_subtractive,
            synthArgs: (freq: 150, cutoff: 2000, res: 1, envAmt: 0.5),

            // Slice track (plan step 4, #95): when sliceTrack is true,
            // this track sounds a chop of the bound sample buffer
            // through the Octatrack slicer instead of its drum
            // SynthDef. sliceIndex is the chop; a per-step p-lock
            // named slice overrides it. sourceTempo is the clip's
            // native BPM when known, nil when unknown — stored, never
            // imposed. The step fires on the project TempoClock (one
            // transport); the chop plays at its native length, so
            // source timing is preserved separately from project
            // tempo. rate is playback rate only: how fast the chop
            // plays, never independent pitch/time stretch.
            // Transform (plan step 5): when transform is \timestretch,
            // the chop sounds through the octahedron_timestretch voice
            // instead of the plain slicer — independent pitch/time:
            // the pointer scans the chop at the tempo-match rate while
            // the grains play at stretchPitch. stretchRate nil means
            // auto: project tempo / sourceTempo when the source tempo
            // is known, the track rate otherwise. stretchPitch 1.0 is
            // the chop's own pitch; stretchGrain is the grain duration
            // in seconds. transform \none is the step-4 direct path.
            sliceTrack: false,
            sliceIndex: 0,
            sourceTempo: nil,
            rate: 1.0,
            transform: \none,
            stretchRate: nil,
            stretchPitch: 1.0,
            stretchGrain: 0.1,

            // Blend sources (synthA, synthB, sampleA, sampleB)
            blend: (synthA: 1.0, synthB: 0.0, sampleA: 0.0, sampleB: 0.0),

            // FX chain params
            fx: (reverbMix: 0, reverbDecay: 1.5, delayMix: 0, delayTime: 0.25,
                 delayFB: 0.3, bitcrush: 0, drive: 0),

            // Humanization
            humanize: (velRand: 0, timeRand: 0, pitchRand: 0, probability: 1),

            // Mute/Solo/Group
            muted: false,
            solo: false,
            muteGroup: nil,  // nil, \A, \B, \C, \D

            // LFOs (3 per track)
            lfos: Array.fill(3, { |j|
                (rate: [1, 2, 0.5][j], shape: 0, phase: 0, bus: nil, synth: nil)
            }),

            // Modulation matrix entries for this track
            modRoutes: List.new,

            // Audio/control buses (allocated by ~golem)
            audioBus: nil,
            fxBus: nil,

            // Active synth nodes
            activeSynths: nil,
            fxSynths: nil
        )
    }),

    // Scene save/recall
    scenes: Dictionary.new,

    // Mute groups
    muteGroups: (\A: List.new, \B: List.new, \C: List.new, \D: List.new),

    // Clipboard for copy/paste
    clipboard: nil,

    // ==========================================
    // TRANSPORT
    // ==========================================
    play: { |self|
        if(self.playing.not) {
            self.playing = true;
            self.currentStep = 0;
            self.clock = TempoClock(self.tempo / 60);

            Tdef(\golem_seq, {
                loop {
                    var stepDur, anyTrackSolo;

                    // Calculate step duration with swing
                    stepDur = 60 / self.tempo / 4; // 16th note

                    // Check if any track is soloed
                    anyTrackSolo = self.tracks.any({ |t| t[\solo] });

                    // Trigger each track
                    self.tracks.do({ |track, trackIdx|
                        var step, shouldPlay, vel, args, pitchOff, timeOff, slice, sliceDur;

                        step = track[\pattern][self.currentStep % track[\steps]];

                        // Determine if this track should sound
                        shouldPlay = step[\active];
                        if(track[\muted]) { shouldPlay = false };
                        if(anyTrackSolo and: { track[\solo].not }) { shouldPlay = false };

                        // Probability gate
                        if(shouldPlay and: { track[\humanize][\probability] < 1.0 }) {
                            if(track[\humanize][\probability].coin.not) {
                                shouldPlay = false;
                            };
                        };

                        if(shouldPlay) {
                            // Velocity with humanization
                            vel = step[\velocity];
                            vel = vel + rrand(track[\humanize][\velRand].neg, track[\humanize][\velRand]);
                            vel = vel.clip(0.01, 1.0);

                            if(track[\sliceTrack]) {
                                // Slice track: sound the bound chop on
                                // this track's bus, on the shared project
                                // transport. Pitch humanization does not
                                // apply: retuning a chop would retime it.
                                slice = track[\sliceIndex];
                                if(step[\pLocks].notNil and: { step[\pLocks][\slice].notNil }) {
                                    slice = step[\pLocks][\slice].asInteger;
                                };
                                sliceDur = self.sliceDuration(track);
                                if(sliceDur.isNil) {
                                    "GOLEM: Slice track % has no buffer loaded - bind a file with /octahedron/load first".format(trackIdx).warn;
                                } {
                                    if(slice < 0 or: { slice >= self.sliceCount }) {
                                        "GOLEM: Slice track % chop % out of range (0..%)".format(trackIdx, slice, self.sliceCount - 1).warn;
                                    } {
                                        if(track[\audioBus].notNil) {
                                            {
                                                // Time randomization (microsecond jitter)
                                                var delay, stretchRate, stretchDur;
                                                delay = rrand(0, track[\humanize][\timeRand].clip(0, 0.05));
                                                delay.wait;
                                                if(track[\transform] == \timestretch) {
                                                    // Transformed chop (plan step 5):
                                                    // the chop sounds through the
                                                    // granular time-stretch voice at
                                                    // the tempo-match rate with
                                                    // independent pitch, for its
                                                    // stretched length — source timing
                                                    // matched to the project tempo,
                                                    // pitch preserved. sliceDur is the
                                                    // native length divided by |rate|,
                                                    // so multiply |rate| back out and
                                                    // divide by the pointer speed.
                                                    stretchRate = self.sliceStretchRate(track);
                                                    stretchDur = sliceDur * track[\rate].abs.max(0.01) / stretchRate.abs.max(0.01);
                                                    ~octahedron_playSliceStretched.(~octahedron_nodes, slice, stretchRate, track[\stretchPitch], track[\stretchGrain], vel, stretchDur, track[\audioBus].index);
                                                } {
                                                    ~octahedron_playSlice.(~octahedron_nodes, slice, track[\rate], vel, sliceDur, track[\audioBus].index);
                                                };
                                            }.fork(self.clock);
                                            ~visual_cortex.target.sendMsg(
                                                "/golem/slice/trigger", trackIdx, slice
                                            );
                                        };
                                    };
                                };
                            } {
                                // Pitch randomization
                                pitchOff = rrand(track[\humanize][\pitchRand].neg, track[\humanize][\pitchRand]);

                                // Build args: base + p-locks
                                args = track[\synthArgs].copy;
                                if(step[\pLocks].notNil) {
                                    step[\pLocks].keysValuesDo({ |k, v|
                                        args[k] = v;
                                    });
                                };

                                // Apply modulation matrix values
                                self.applyModulation(track, self.currentStep, args);

                                // Apply automation
                                track[\automation].keysValuesDo({ |param, values|
                                    if(values[self.currentStep % track[\steps]].notNil) {
                                        args[param.asSymbol] = values[self.currentStep % track[\steps]];
                                    };
                                });

                                // Add pitch offset
                                args[\freq] = (args[\freq] ? 150) + pitchOff;

                                // Trigger synth
                                if(track[\audioBus].notNil) {
                                    {
                                        // Time randomization (microsecond jitter)
                                        var delay = rrand(0, track[\humanize][\timeRand].clip(0, 0.05));
                                        delay.wait;

                                        Synth(track[\synthDef],
                                            [\outBus, track[\audioBus].index,
                                             \velocity, vel, \gate, 1] ++ args.asPairs,
                                            target: ~sc_grp[\te]
                                        );
                                    }.fork(self.clock);
                                };
                            };

                            // Broadcast trigger to Visual Cortex
                            ~visual_cortex.target.sendMsg(
                                "/golem/track/trigger", trackIdx, vel
                            );
                        };
                    });

                    // Broadcast step position
                    ~visual_cortex.target.sendMsg(
                        "/golem/step", self.currentStep
                    );
                    ~visual_cortex.target.sendMsg(
                        "/golem/seq/state", 1, self.tempo, self.currentStep
                    );

                    // Advance step
                    self.currentStep = self.currentStep + 1;

                    // Swing: offset odd steps
                    if((self.currentStep % 2) == 1) {
                        var maxSwing = self.tracks.collect({ |t| t[\swing] }).maxItem;
                        (stepDur + (stepDur * maxSwing * 0.33)).wait;
                    } {
                        stepDur.wait;
                    };
                };
            }).play;

            "GOLEM: Sequencer playing at % BPM".format(self.tempo).postln;
        };
    },

    stop: { |self|
        if(self.playing) {
            self.playing = false;
            Tdef(\golem_seq).stop;
            self.currentStep = 0;
            ~visual_cortex.target.sendMsg("/golem/seq/state", 0, self.tempo, 0);
            "GOLEM: Sequencer stopped".postln;
        };
    },

    setTempo: { |self, bpm|
        self.tempo = bpm.clip(30, 300);
        if(self.clock.notNil) {
            self.clock.tempo = self.tempo / 60;
        };
        "GOLEM: Tempo set to % BPM".format(self.tempo).postln;
    },

    // Native length (seconds) of one chop of the bound buffer at the
    // track's playback rate, or nil when no buffer is bound or the
    // slicer is not loaded. The chop plays at its source length: the
    // step fires on the project clock, the sound keeps source timing
    // (plan step 4). Rate divides by its absolute value so a reversed
    // chop (negative rate) still reports its true length.
    sliceDuration: { |self, track|
        var nodes, buf, dur;
        nodes = ~octahedron_nodes;
        if(nodes.isNil or: { ~octahedron_playSlice.isNil }) { ^nil };
        buf = nodes[\sliceBuf];
        if(buf.isNil) { ^nil };
        dur = (buf.numFrames / (nodes[\numSlices] ? 16)) / buf.sampleRate;
        ^(dur / track[\rate].abs.max(0.01));
    },

    // Chop count of the bound buffer (16 when unknown), for the
    // trigger range check. Never touches the project clock.
    sliceCount: { |self|
        var nodes = ~octahedron_nodes;
        if(nodes.isNil) { ^16 };
        ^(nodes[\numSlices] ? 16);
    },

    // Pointer speed for a stretched chop (plan step 5): the explicit
    // stretchRate when set, else the tempo-match rate — project tempo /
    // source tempo — when the source tempo is known, else the track's
    // playback rate. Clipped to the voice's 0.01..4 range. A 100 BPM
    // chop in a 120 BPM project scans at 1.2 with its pitch preserved;
    // that is the tempo match step 4 deferred to this voice.
    sliceStretchRate: { |self, track|
        var rate;
        if(track[\stretchRate].notNil) {
            rate = track[\stretchRate];
        } {
            if(track[\sourceTempo].notNil) {
                rate = self.tempo / track[\sourceTempo];
            } {
                rate = track[\rate];
            };
        };
        ^rate.clip(0.01, 4);
    },

    // ==========================================
    // PATTERN EDITING
    // ==========================================
    toggleStep: { |self, trackIdx, stepIdx|
        var step = self.tracks[trackIdx][\pattern][stepIdx];
        step[\active] = step[\active].not;
    },

    setStepVelocity: { |self, trackIdx, stepIdx, vel|
        self.tracks[trackIdx][\pattern][stepIdx][\velocity] = vel.clip(0.01, 1.0);
    },

    setStepPLock: { |self, trackIdx, stepIdx, param, value|
        var step = self.tracks[trackIdx][\pattern][stepIdx];
        if(step[\pLocks].isNil) { step[\pLocks] = Dictionary.new };
        step[\pLocks][param.asSymbol] = value;
    },

    clearStepPLock: { |self, trackIdx, stepIdx, param|
        var step = self.tracks[trackIdx][\pattern][stepIdx];
        if(step[\pLocks].notNil) {
            step[\pLocks].removeAt(param.asSymbol);
            if(step[\pLocks].isEmpty) { step[\pLocks] = nil };
        };
    },

    // ==========================================
    // COPY/PASTE
    // ==========================================
    copyPattern: { |self, trackIdx|
        self.clipboard = self.tracks[trackIdx][\pattern].deepCopy;
        "GOLEM: Pattern from track % copied".format(trackIdx).postln;
    },

    pastePattern: { |self, trackIdx|
        if(self.clipboard.notNil) {
            self.tracks[trackIdx][\pattern] = self.clipboard.deepCopy;
            "GOLEM: Pattern pasted to track %".format(trackIdx).postln;
        };
    },

    // ==========================================
    // SCENES
    // ==========================================
    saveScene: { |self, name|
        self.scenes[name.asSymbol] = self.tracks.collect({ |t|
            (
                pattern: t[\pattern].deepCopy,
                synthDef: t[\synthDef],
                synthArgs: t[\synthArgs].copy,
                blend: t[\blend].copy,
                fx: t[\fx].copy,
                muted: t[\muted],
                solo: t[\solo],
                sliceTrack: t[\sliceTrack],
                sliceIndex: t[\sliceIndex],
                sourceTempo: t[\sourceTempo],
                rate: t[\rate],
                transform: t[\transform],
                stretchRate: t[\stretchRate],
                stretchPitch: t[\stretchPitch],
                stretchGrain: t[\stretchGrain]
            )
        });
        "GOLEM: Scene '%' saved".format(name).postln;
    },

    loadScene: { |self, name|
        var scene = self.scenes[name.asSymbol];
        if(scene.notNil) {
            scene.do({ |data, i|
                self.tracks[i][\pattern] = data[\pattern].deepCopy;
                self.tracks[i][\synthDef] = data[\synthDef];
                self.tracks[i][\synthArgs] = data[\synthArgs].copy;
                self.tracks[i][\blend] = data[\blend].copy;
                self.tracks[i][\fx] = data[\fx].copy;
                self.tracks[i][\muted] = data[\muted];
                self.tracks[i][\solo] = data[\solo];
                // Slice fields default for scenes saved before step 4.
                self.tracks[i][\sliceTrack] = data[\sliceTrack] ? false;
                self.tracks[i][\sliceIndex] = data[\sliceIndex] ? 0;
                self.tracks[i][\sourceTempo] = data[\sourceTempo];
                self.tracks[i][\rate] = data[\rate] ? 1.0;
                // Transform fields default for scenes saved before step 5.
                self.tracks[i][\transform] = data[\transform] ? \none;
                self.tracks[i][\stretchRate] = data[\stretchRate];
                self.tracks[i][\stretchPitch] = data[\stretchPitch] ? 1.0;
                self.tracks[i][\stretchGrain] = data[\stretchGrain] ? 0.1;
            });
            "GOLEM: Scene '%' loaded".format(name).postln;
        } {
            "GOLEM: Scene '%' not found".format(name).warn;
        };
    },

    // ==========================================
    // MUTE GROUPS
    // ==========================================
    setMuteGroup: { |self, trackIdx, group|
        // Remove from old group
        [\A, \B, \C, \D].do({ |g|
            self.muteGroups[g].remove(trackIdx);
        });
        // Add to new group
        if(group.notNil) {
            self.tracks[trackIdx][\muteGroup] = group.asSymbol;
            self.muteGroups[group.asSymbol].add(trackIdx);
        } {
            self.tracks[trackIdx][\muteGroup] = nil;
        };
    },

    toggleMuteGroup: { |self, group|
        var members = self.muteGroups[group.asSymbol];
        if(members.notNil) {
            var allMuted = members.every({ |idx| self.tracks[idx][\muted] });
            members.do({ |idx|
                self.tracks[idx][\muted] = allMuted.not;
                ~visual_cortex.target.sendMsg(
                    "/golem/track/state", idx,
                    self.tracks[idx][\muted].asInteger,
                    self.tracks[idx][\solo].asInteger
                );
            });
        };
    },

    // ==========================================
    // MODULATION MATRIX
    // ==========================================
    // Sources: lfo1, lfo2, lfo3, env, random, stepPos, velocity, xyPadX, xyPadY, synthA, synthB
    // Dests: synthA.freq, synthA.cutoff, synthA.res, synthA.ampEnv.d,
    //        synthB.freq, synthB.cutoff, blend.synthA, blend.synthB,
    //        blend.sampleA, blend.sampleB, pan, drive, delayMix, reverbMix, bitcrush

    modSources: [\lfo1, \lfo2, \lfo3, \env, \random, \stepPos, \velocity,
                 \xyPadX, \xyPadY, \synthA, \synthB],

    modDests: [\synthA_freq, \synthA_cutoff, \synthA_res, \synthA_decay,
               \synthB_freq, \synthB_cutoff,
               \blend_synthA, \blend_synthB, \blend_sampleA, \blend_sampleB,
               \pan, \drive, \delayMix, \reverbMix, \bitcrush],

    // XY pad state (shared across tracks)
    xyPad: (x: 0.5, y: 0.5),

    addModRoute: { |self, trackIdx, source, dest, amount|
        self.tracks[trackIdx][\modRoutes].add(
            (source: source.asSymbol, dest: dest.asSymbol, amount: amount.clip(-1, 1))
        );
        "GOLEM: Mod route added (track %, % -> % @ %)".format(trackIdx, source, dest, amount).postln;
    },

    removeModRoute: { |self, trackIdx, index|
        if(index < self.tracks[trackIdx][\modRoutes].size) {
            self.tracks[trackIdx][\modRoutes].removeAt(index);
        };
    },

    setModAmount: { |self, trackIdx, index, amount|
        if(index < self.tracks[trackIdx][\modRoutes].size) {
            self.tracks[trackIdx][\modRoutes][index][\amount] = amount.clip(-1, 1);
        };
    },

    // Resolve a mod source value at trigger time
    resolveModSource: { |self, track, source, step|
        var val = 0;
        case
        { source == \lfo1 } { val = track[\lfos][0][\bus].notNil.if({ track[\lfos][0][\bus].getSynchronous }, 0) }
        { source == \lfo2 } { val = track[\lfos][1][\bus].notNil.if({ track[\lfos][1][\bus].getSynchronous }, 0) }
        { source == \lfo3 } { val = track[\lfos][2][\bus].notNil.if({ track[\lfos][2][\bus].getSynchronous }, 0) }
        { source == \env } { val = 0 }  // placeholder — would read from envelope follower bus
        { source == \random } { val = rrand(-1.0, 1.0) }
        { source == \stepPos } { val = (step / (track[\steps] - 1)).linlin(0, 1, -1, 1) }
        { source == \velocity } { val = track[\pattern][step % track[\steps]][\velocity].linlin(0, 1, -1, 1) }
        { source == \xyPadX } { val = self.xyPad[\x].linlin(0, 1, -1, 1) }
        { source == \xyPadY } { val = self.xyPad[\y].linlin(0, 1, -1, 1) }
        { source == \synthA } { val = 0 }
        { source == \synthB } { val = 0 };

        ^val;
    },

    // Map dest name to actual SynthDef param
    destToParam: { |self, dest|
        var map = (
            synthA_freq: \freq,
            synthA_cutoff: \cutoff,
            synthA_res: \res,
            synthA_decay: \dec,
            synthB_freq: \freq,
            synthB_cutoff: \cutoff,
            blend_synthA: \blendA,
            blend_synthB: \blendB,
            blend_sampleA: \blendSA,
            blend_sampleB: \blendSB,
            pan: \pan,
            drive: \drive,
            delayMix: \delayMix,
            reverbMix: \reverbMix,
            bitcrush: \bitcrush
        );
        ^map[dest];
    },

    // Apply all mod routes for a track at trigger time
    applyModulation: { |self, track, step, args|
        track[\modRoutes].do({ |route|
            var srcVal = self.resolveModSource(track, route[\source], step);
            var param = self.destToParam(route[\dest]);
            var modVal = srcVal * route[\amount];

            if(param.notNil and: { args[param].notNil }) {
                args[param] = args[param] + (modVal * args[param].abs.max(1));
            };
        });
    },

    // ==========================================
    // LFO MANAGEMENT
    // ==========================================
    startLFOs: { |self|
        self.tracks.do({ |track, ti|
            track[\lfos].do({ |lfo, li|
                if(lfo[\bus].isNil) {
                    lfo[\bus] = Bus.control(s, 1);
                };
                if(lfo[\synth].notNil) { lfo[\synth].free };
                lfo[\synth] = Synth(\golem_lfo, [
                    \outBus, lfo[\bus].index,
                    \rate, lfo[\rate],
                    \shape, lfo[\shape],
                    \phase, lfo[\phase]
                ]);
            });
        });
        "GOLEM: LFOs started (24 total)".postln;
    },

    stopLFOs: { |self|
        self.tracks.do({ |track|
            track[\lfos].do({ |lfo|
                if(lfo[\synth].notNil) { lfo[\synth].free; lfo[\synth] = nil };
            });
        });
        "GOLEM: LFOs stopped".postln;
    },

    setLFOParam: { |self, trackIdx, lfoIdx, param, value|
        var lfo = self.tracks[trackIdx][\lfos][lfoIdx];
        lfo[param.asSymbol] = value;
        if(lfo[\synth].notNil) {
            lfo[\synth].set(param.asSymbol, value);
        };
        ~visual_cortex.target.sendMsg(
            "/golem/lfo/value", trackIdx, lfoIdx, value
        );
    },

    // ==========================================
    // OSC RESPONDERS
    // ==========================================
    initOSC: { |self|
        // Transport
        OSCdef(\golem_play, { self.play }, "/golem/transport/play");
        OSCdef(\golem_stop, { self.stop }, "/golem/transport/stop");
        OSCdef(\golem_tempo, { |msg| self.setTempo(msg[1]) }, "/golem/transport/tempo");

        // Track control
        OSCdef(\golem_track_mute, { |msg|
            var idx = msg[1].asInteger;
            self.tracks[idx][\muted] = self.tracks[idx][\muted].not;
            ~visual_cortex.target.sendMsg("/golem/track/state", idx,
                self.tracks[idx][\muted].asInteger, self.tracks[idx][\solo].asInteger);
        }, "/golem/track/mute");

        OSCdef(\golem_track_solo, { |msg|
            var idx = msg[1].asInteger;
            self.tracks[idx][\solo] = self.tracks[idx][\solo].not;
            ~visual_cortex.target.sendMsg("/golem/track/state", idx,
                self.tracks[idx][\muted].asInteger, self.tracks[idx][\solo].asInteger);
        }, "/golem/track/solo");

        // Step editing
        OSCdef(\golem_step_toggle, { |msg|
            self.toggleStep(msg[1].asInteger, msg[2].asInteger);
        }, "/golem/step/toggle");

        OSCdef(\golem_step_vel, { |msg|
            self.setStepVelocity(msg[1].asInteger, msg[2].asInteger, msg[3].asFloat);
        }, "/golem/step/velocity");

        OSCdef(\golem_step_plock, { |msg|
            self.setStepPLock(msg[1].asInteger, msg[2].asInteger, msg[3], msg[4].asFloat);
        }, "/golem/step/plock");

        // Engine params
        OSCdef(\golem_engine_param, { |msg|
            var trackIdx = msg[1].asInteger;
            var param = msg[2].asSymbol;
            var value = msg[3].asFloat;
            self.tracks[trackIdx][\synthArgs][param] = value;
            ~visual_cortex.target.sendMsg("/golem/engine/state", trackIdx,
                self.tracks[trackIdx][\synthDef], value, value);
        }, "/golem/engine/param");

        // LFO params
        OSCdef(\golem_lfo_param, { |msg|
            self.setLFOParam(msg[1].asInteger, msg[2].asInteger, msg[3], msg[4].asFloat);
        }, "/golem/lfo/param");

        // Modulation
        OSCdef(\golem_mod_add, { |msg|
            self.addModRoute(msg[1].asInteger, msg[2], msg[3], msg[4].asFloat);
        }, "/golem/mod/add");

        OSCdef(\golem_mod_remove, { |msg|
            self.removeModRoute(msg[1].asInteger, msg[2].asInteger);
        }, "/golem/mod/remove");

        OSCdef(\golem_mod_amount, { |msg|
            self.setModAmount(msg[1].asInteger, msg[2].asInteger, msg[3].asFloat);
        }, "/golem/mod/amount");

        // FX
        OSCdef(\golem_fx_param, { |msg|
            var trackIdx = msg[1].asInteger;
            var fxName = msg[2].asSymbol;
            var param = msg[3].asSymbol;
            var value = msg[4].asFloat;
            self.tracks[trackIdx][\fx][param] = value;
            // Update running FX synth if present
            if(self.tracks[trackIdx][\fxSynths].notNil) {
                self.tracks[trackIdx][\fxSynths].do({ |syn|
                    syn.set(param, value);
                });
            };
        }, "/golem/fx/param");

        // Preset
        OSCdef(\golem_preset_load, { |msg|
            var trackIdx = msg[1].asInteger;
            var name = msg[2].asSymbol;
            var preset = ~golem_patterns.factory[name];
            if(preset.isNil) { preset = ~golem_patterns.loadPreset(name) };
            if(preset.notNil) {
                self.tracks[trackIdx][\synthDef] = preset[\synthDef];
                self.tracks[trackIdx][\synthArgs] = preset[\args].copy;
            };
        }, "/golem/preset/load");

        OSCdef(\golem_preset_save, { |msg|
            var trackIdx = msg[1].asInteger;
            var name = msg[2].asString;
            ~golem_patterns.savePreset(name, (
                synthDef: self.tracks[trackIdx][\synthDef],
                args: self.tracks[trackIdx][\synthArgs].copy
            ));
        }, "/golem/preset/save");

        // Scene
        OSCdef(\golem_scene_save, { |msg| self.saveScene(msg[1]) }, "/golem/scene/save");
        OSCdef(\golem_scene_load, { |msg| self.loadScene(msg[1]) }, "/golem/scene/load");

        // Pad trigger (immediate play)
        OSCdef(\golem_pad_trigger, { |msg|
            var trackIdx = msg[1].asInteger;
            var vel = msg[2].asFloat;
            var track = self.tracks[trackIdx];
            if(track[\audioBus].notNil) {
                Synth(track[\synthDef],
                    [\outBus, track[\audioBus].index,
                     \velocity, vel, \gate, 1] ++ track[\synthArgs].asPairs,
                    target: ~sc_grp[\te]
                );
            };
        }, "/golem/pad/trigger");

        // Slice tracks (plan step 4): bind a Golem track to a chop of
        // the bound sample buffer so the sequencer sounds slices on
        // the shared project transport. /golem/slice/bind
        // <track:int> <slice:int> [sourceTempo:float] — sourceTempo
        // is the clip's native BPM when known (0 or omitted =
        // unknown); it is stored for later steps and never retunes
        // the voice. /golem/slice/rate sets playback rate only —
        // never independent pitch/time stretch (that is the
        // octahedron_timestretch voice, plan step 5).
        // /golem/slice/transform <track:int> <name:symbol> routes the
        // track's chops through one transformation: \none (the direct
        // slicer path) or \timestretch (the granular time-stretch
        // voice, independent pitch/time). Unknown names are rejected
        // with a warn and leave the track unchanged.
        // /golem/slice/stretch <track:int> [rate:float] [pitch:float]
        // [grainSize:float] sets the stretch voice's controls: rate 0
        // or omitted means auto tempo-match (project tempo / source
        // tempo, resolved at the step); pitch 1.0 is the chop's own
        // pitch; grainSize is the grain duration in seconds. All five
        // reply on /golem/slice/state
        // <track> <slice> <sourceTempo|0> <rate> <transform>
        // <stretchRate|0> <stretchPitch> <stretchGrain> — the first
        // four args keep their step-4 positions; unbind reports
        // slice -1 with the transform fields at their defaults.
        OSCdef(\golem_slice_bind, { |msg|
            var trackIdx = msg[1].asInteger;
            var slice = msg[2].asInteger.max(0);
            var tempo = msg[3] !? _.asFloat ?? 0;
            var track;
            if(trackIdx < 0 or: { trackIdx >= self.tracks.size }) {
                "GOLEM: Slice bind: track % out of range".format(trackIdx).warn;
            } {
                track = self.tracks[trackIdx];
                track[\sliceTrack] = true;
                track[\sliceIndex] = slice;
                track[\sourceTempo] = if(tempo > 0) { tempo } { nil };
                ~visual_cortex.target.sendMsg("/golem/slice/state",
                    trackIdx, track[\sliceIndex], track[\sourceTempo] ? 0, track[\rate],
                    track[\transform], track[\stretchRate] ? 0, track[\stretchPitch], track[\stretchGrain]);
                "GOLEM: Track % bound to slice % (source tempo %)".format(
                    trackIdx, track[\sliceIndex], track[\sourceTempo] ? "unknown").postln;
            };
        }, "/golem/slice/bind");

        OSCdef(\golem_slice_rate, { |msg|
            var trackIdx = msg[1].asInteger;
            var rate = msg[2].asFloat.clip(-4, 4);
            var track;
            if(trackIdx < 0 or: { trackIdx >= self.tracks.size }) {
                "GOLEM: Slice rate: track % out of range".format(trackIdx).warn;
            } {
                track = self.tracks[trackIdx];
                track[\rate] = rate;
                ~visual_cortex.target.sendMsg("/golem/slice/state",
                    trackIdx, track[\sliceIndex], track[\sourceTempo] ? 0, track[\rate],
                    track[\transform], track[\stretchRate] ? 0, track[\stretchPitch], track[\stretchGrain]);
                "GOLEM: Track % playback rate % (rate only, not pitch/time stretch)".format(trackIdx, rate).postln;
            };
        }, "/golem/slice/rate");

        OSCdef(\golem_slice_transform, { |msg|
            var trackIdx = msg[1].asInteger;
            var name = msg[2] !? _.asSymbol ?? \none;
            var track;
            if(trackIdx < 0 or: { trackIdx >= self.tracks.size }) {
                "GOLEM: Slice transform: track % out of range".format(trackIdx).warn;
            } {
                if((name != \none) and: { name != \timestretch }) {
                    "GOLEM: Slice transform: unknown transform % (none, timestretch)".format(name).warn;
                } {
                    track = self.tracks[trackIdx];
                    track[\transform] = name;
                    ~visual_cortex.target.sendMsg("/golem/slice/state",
                        trackIdx, track[\sliceIndex], track[\sourceTempo] ? 0, track[\rate],
                        track[\transform], track[\stretchRate] ? 0, track[\stretchPitch], track[\stretchGrain]);
                    "GOLEM: Track % slice transform %".format(trackIdx, name).postln;
                };
            };
        }, "/golem/slice/transform");

        OSCdef(\golem_slice_stretch, { |msg|
            var trackIdx = msg[1].asInteger;
            var rate = msg[2] !? _.asFloat;
            var pitch = msg[3] !? _.asFloat;
            var grain = msg[4] !? _.asFloat;
            var track;
            if(trackIdx < 0 or: { trackIdx >= self.tracks.size }) {
                "GOLEM: Slice stretch: track % out of range".format(trackIdx).warn;
            } {
                track = self.tracks[trackIdx];
                // rate 0 (or omitted) = auto tempo-match: store nil and
                // let the step resolve project tempo / source tempo.
                track[\stretchRate] = if(rate.notNil and: { rate > 0 }) { rate.clip(0.01, 4) } { nil };
                if(pitch.notNil) { track[\stretchPitch] = pitch.clip(0.25, 4) };
                if(grain.notNil) { track[\stretchGrain] = grain.clip(0.01, 1) };
                ~visual_cortex.target.sendMsg("/golem/slice/state",
                    trackIdx, track[\sliceIndex], track[\sourceTempo] ? 0, track[\rate],
                    track[\transform], track[\stretchRate] ? 0, track[\stretchPitch], track[\stretchGrain]);
                "GOLEM: Track % slice stretch rate % pitch % grain %".format(
                    trackIdx, track[\stretchRate] ? "auto", track[\stretchPitch], track[\stretchGrain]).postln;
            };
        }, "/golem/slice/stretch");

        OSCdef(\golem_slice_unbind, { |msg|
            var trackIdx = msg[1].asInteger;
            var track;
            if(trackIdx < 0 or: { trackIdx >= self.tracks.size }) {
                "GOLEM: Slice unbind: track % out of range".format(trackIdx).warn;
            } {
                track = self.tracks[trackIdx];
                track[\sliceTrack] = false;
                track[\sliceIndex] = 0;
                track[\sourceTempo] = nil;
                track[\rate] = 1.0;
                // The transform fields are slice fields: unbinding
                // returns them to their defaults with the chop.
                track[\transform] = \none;
                track[\stretchRate] = nil;
                track[\stretchPitch] = 1.0;
                track[\stretchGrain] = 0.1;
                ~visual_cortex.target.sendMsg("/golem/slice/state",
                    trackIdx, -1, 0, 1.0, \none, 0, 1.0, 0.1);
                "GOLEM: Track % unbound from slices".format(trackIdx).postln;
            };
        }, "/golem/slice/unbind");

        // XY pad
        OSCdef(\golem_xy, { |msg|
            self.xyPad[\x] = msg[1].asFloat;
            self.xyPad[\y] = msg[2].asFloat;
        }, "/golem/xy/update");

        // Mute groups
        OSCdef(\golem_mutegroup, { |msg|
            self.toggleMuteGroup(msg[1]);
        }, "/golem/mutegroup/toggle");

        // Generative
        OSCdef(\golem_gen_variation, { |msg|
            var trackIdx = msg[1].asInteger;
            var amount = msg[2] !? { msg[2].asFloat } ?? 0.3;
            self.tracks[trackIdx][\pattern] = ~golem_patterns.generateVariation(
                self.tracks[trackIdx][\pattern], amount
            );
        }, "/golem/gen/variation");

        OSCdef(\golem_gen_fill, { |msg|
            var trackIdx = msg[1].asInteger;
            var fillLen = msg[2] !? { msg[2].asInteger } ?? 4;
            var density = msg[3] !? { msg[3].asFloat } ?? 0.75;
            self.tracks[trackIdx][\pattern] = ~golem_patterns.generateFill(
                self.tracks[trackIdx][\steps], fillLen, density
            );
        }, "/golem/gen/fill");

        "GOLEM: OSC responders initialized".postln;
    }
);

"--- BRAHMA: Golem Sequencer Engine Loaded ---".postln;
)
