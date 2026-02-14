/*
  Phase 6: MAGNUM OPUS — OCTAHEDRON (Octatrack Features)
  Crossfader Scenes, Pickup Machine, Time-Stretch,
  Slice Machine, Arranger, Cue Output
*/

(
// ==========================================
// 1. CROSSFADER — Scene A/B blending
// ==========================================
// Blends two stereo buses with selectable crossfade curve.
// Equal-power (curve=0) preserves loudness; linear (curve=1) for DJ-style.
SynthDef(\octahedron_crossfader, {
    |inBusA=0, inBusB=0, outBus=0, xfade=0.5, curve=0|

    var sigA, sigB, mix;
    var xf, gainA, gainB;

    sigA = In.ar(inBusA, 2);
    sigB = In.ar(inBusB, 2);

    xf = xfade.clip(0, 1);

    // Equal power: cos/sin law preserves apparent loudness at center
    // Linear: straight amplitude crossfade
    gainA = Select.kr(curve.clip(0, 1).round, [
        (1 - xf).sqrt,   // Equal power (cos/sin approximation)
        1 - xf            // Linear
    ]);
    gainB = Select.kr(curve.clip(0, 1).round, [
        xf.sqrt,          // Equal power
        xf                // Linear
    ]);

    mix = (sigA * gainA) + (sigB * gainB);

    Out.ar(outBus, mix);
}).add;

// ==========================================
// 2. PICKUP MACHINE — Live loop recorder/overdub
// ==========================================
// Records live input to a buffer with overdub and multiply.
// record>0.5 arms recording; overdub mixes new audio over existing content.
// feedback controls how much of the existing buffer survives each overdub pass.
SynthDef(\octahedron_pickup, {
    |inBus=0, outBus=0, bufnum=0, record=0, overdub=0,
     multiply=0, level=1.0, feedback=0.8|

    var in, play, recPhase, isRecording, isOverdubbing;
    var recLevel, preLevel;

    in = In.ar(inBus, 1);

    isRecording = (record > 0.5);
    isOverdubbing = (overdub > 0.5);

    // RecordBuf levels:
    //   recLevel = how much new input goes in
    //   preLevel = how much existing content is preserved
    recLevel = Select.kr(isRecording, [
        Select.kr(isOverdubbing, [0, 1]),  // Not recording: 0 or overdub
        1                                    // Recording: full input
    ]);
    preLevel = Select.kr(isRecording, [
        Select.kr(isOverdubbing, [1, feedback.clip(0, 1)]),  // Not rec: full preserve or feedback
        0                                                       // Recording: wipe existing
    ]);

    // Write to buffer
    RecordBuf.ar(in, bufnum,
        recLevel: recLevel,
        preLevel: preLevel,
        run: (isRecording + isOverdubbing).min(1),
        loop: 1
    );

    // Playback
    play = PlayBuf.ar(1, bufnum, BufRateScale.kr(bufnum), loop: 1);

    Out.ar(outBus, play * level.clip(0, 2));
}).add;

// ==========================================
// 3. TIME STRETCH — Granular phase vocoder
// ==========================================
// Independent rate and pitch control via GrainBuf.
// rate controls playback speed (pointer movement), pitch shifts grain playback.
SynthDef(\octahedron_timestretch, {
    |inBus=0, outBus=0, bufnum=0, rate=1.0, pitch=1.0,
     grainSize=0.1, overlap=4|

    var pointer, grains, trig;
    var grainFreq, grainDur;

    // Grain trigger frequency derived from overlap and grain size
    grainDur = grainSize.clip(0.01, 1.0);
    grainFreq = overlap.clip(1, 16) / grainDur;
    trig = Impulse.ar(grainFreq);

    // Playback pointer: rate controls how fast we scan through the buffer
    pointer = Phasor.ar(
        trig: 0,
        rate: rate.clip(0.01, 4.0) * BufRateScale.kr(bufnum) * SampleDur.ir,
        start: 0,
        end: 1
    );

    // GrainBuf: pos is 0-1 normalized, rate here controls pitch
    grains = GrainBuf.ar(
        numChannels: 2,
        trigger: trig,
        dur: grainDur,
        sndbuf: bufnum,
        rate: pitch.clip(0.25, 4.0),
        pos: pointer,
        interp: 4,  // Cubic interpolation
        pan: 0
    );

    Out.ar(outBus, grains);
}).add;

// ==========================================
// 4. SLICER — Sample slice playback
// ==========================================
// Divides a buffer into numSlices equal regions.
// sliceIndex selects which slice to trigger with per-slice enveloping.
SynthDef(\octahedron_slicer, {
    |outBus=0, bufnum=0, sliceIndex=0, numSlices=16,
     gate=1, rate=1.0, startPos=0|

    var sliceStart, sliceLen, play, env;
    var numFrames, sliceFrames;

    numFrames = BufFrames.kr(bufnum);
    sliceFrames = numFrames / numSlices.clip(1, 128);

    // Calculate slice start position (overrides startPos if sliceIndex > 0)
    sliceStart = Select.kr(sliceIndex.clip(0, numSlices - 1) > 0, [
        startPos.clip(0, 1) * numFrames,
        sliceIndex.clip(0, numSlices - 1) * sliceFrames
    ]);

    // Envelope gates the slice duration
    env = EnvGen.ar(
        Env.asr(0.001, 1, 0.005),
        gate,
        doneAction: 2
    );

    // Playback from slice start
    play = PlayBuf.ar(
        numChannels: 1,
        bufnum: bufnum,
        rate: rate.clip(-4, 4) * BufRateScale.kr(bufnum),
        startPos: sliceStart,
        loop: 0
    );

    Out.ar(outBus, play * env);
}).add;

// ==========================================
// 5. CUE OUTPUT — Dual-destination router
// ==========================================
// Routes a stereo input to both main and cue buses with independent levels.
// Enables DJ-style pre-listen/headphone monitoring.
SynthDef(\octahedron_cue, {
    |inBus=0, cueBus=0, mainBus=0, cueLevel=1.0, mainLevel=1.0|

    var sig;

    sig = In.ar(inBus, 2);

    // Main output
    Out.ar(mainBus, sig * mainLevel.clip(0, 2));

    // Cue/pre-listen output (independent bus for headphones)
    Out.ar(cueBus, sig * cueLevel.clip(0, 2));
}).add;

// ==========================================
// 6. ARRANGER — Language-side chain sequencer
// ==========================================
// Octatrack-style arranger: chains of patterns with repeat counts
// and conditional logic for live arrangement.
~OCTAHEDRON_ARRANGER = (
    chains: List.new,      // Each: (pattern: idx, repeats: N, condition: \always)
    currentChain: 0,
    currentRepeat: 0,
    running: false,

    // Add a chain entry
    addChain: { |self, pattern, repeats, condition|
        self[\chains].add((
            pattern: pattern,
            repeats: repeats ? 1,
            condition: condition ? \always
        ));
        "OCTAHEDRON ARRANGER: Added chain % (pat: %, reps: %, cond: %)".format(
            self[\chains].size - 1, pattern, repeats ? 1, condition ? \always
        ).postln;
    },

    // Advance through chains, handle repeats and conditions.
    // Returns pattern index or nil if arrangement is complete.
    advance: { |self|
        var result = nil;
        var chain;

        if(self[\running] and: { self[\chains].size > 0 }) {
            chain = self[\chains][self[\currentChain]];

            if(chain.notNil) {
                var shouldPlay = true;

                // Evaluate condition
                switch(chain[\condition],
                    \always, { shouldPlay = true },
                    \first, { shouldPlay = (self[\currentRepeat] == 0) },
                    \last, { shouldPlay = (self[\currentRepeat] == (chain[\repeats] - 1)) },
                    \even, { shouldPlay = (self[\currentRepeat] % 2 == 0) },
                    \odd, { shouldPlay = (self[\currentRepeat] % 2 == 1) },
                    \random50, { shouldPlay = (0.5.coin) },
                    \random75, { shouldPlay = (0.75.coin) }
                );

                if(shouldPlay) { result = chain[\pattern] };

                // Advance repeat counter
                self[\currentRepeat] = self[\currentRepeat] + 1;

                // Move to next chain when repeats exhausted
                if(self[\currentRepeat] >= chain[\repeats]) {
                    self[\currentRepeat] = 0;
                    self[\currentChain] = self[\currentChain] + 1;

                    // Check if arrangement is complete
                    if(self[\currentChain] >= self[\chains].size) {
                        self[\running] = false;
                        "OCTAHEDRON ARRANGER: Arrangement complete".postln;
                    };
                };
            };
        };

        result;
    },

    // Start the arranger from the beginning
    start: { |self|
        self[\currentChain] = 0;
        self[\currentRepeat] = 0;
        self[\running] = true;
        "OCTAHEDRON ARRANGER: Started (% chains)".format(self[\chains].size).postln;
    },

    // Stop the arranger
    stop: { |self|
        self[\running] = false;
        "OCTAHEDRON ARRANGER: Stopped".postln;
    },

    // Reset to beginning without starting
    reset: { |self|
        self[\currentChain] = 0;
        self[\currentRepeat] = 0;
        self[\running] = false;
        "OCTAHEDRON ARRANGER: Reset".postln;
    },

    // Clear all chains
    clear: { |self|
        self[\chains] = List.new;
        self[\currentChain] = 0;
        self[\currentRepeat] = 0;
        self[\running] = false;
        "OCTAHEDRON ARRANGER: Cleared".postln;
    },

    // Remove a specific chain by index
    removeChain: { |self, idx|
        if(idx < self[\chains].size) {
            self[\chains].removeAt(idx);
            // Adjust current position if needed
            if(self[\currentChain] > idx) {
                self[\currentChain] = (self[\currentChain] - 1).max(0);
            };
        };
    },

    // Insert a chain at a specific position
    insertChain: { |self, idx, pattern, repeats, condition|
        self[\chains].insert(idx.clip(0, self[\chains].size), (
            pattern: pattern,
            repeats: repeats ? 1,
            condition: condition ? \always
        ));
        // Adjust current position if inserting before it
        if(self[\currentChain] >= idx) {
            self[\currentChain] = self[\currentChain] + 1;
        };
    }
);

// ==========================================
// OSC RESPONDERS — /octahedron/*
// ==========================================

// Crossfader control: /octahedron/crossfade <xfade:float> <curve:int>
OSCdef(\octahedron_xfade, { |msg|
    var xfade = msg[1].asFloat;
    var curve = msg[2] !? _.asInteger ?? 0;
    // Set on any running crossfader synths via named node or group
    ~OCTAHEDRON_NODES !? { |nodes|
        nodes[\crossfader] !? { |syn|
            syn.set(\xfade, xfade.clip(0, 1), \curve, curve.clip(0, 1));
        };
    };
    ~VISUAL_CORTEX.target.sendMsg("/octahedron/crossfade/state", xfade, curve);
}, "/octahedron/crossfade");

// Pickup machine record control: /octahedron/record <record:int> <overdub:int>
OSCdef(\octahedron_record, { |msg|
    var record = msg[1].asInteger;
    var overdub = msg[2] !? _.asInteger ?? 0;
    ~OCTAHEDRON_NODES !? { |nodes|
        nodes[\pickup] !? { |syn|
            syn.set(\record, record, \overdub, overdub);
        };
    };
    ~VISUAL_CORTEX.target.sendMsg("/octahedron/record/state", record, overdub);
}, "/octahedron/record");

// Pickup feedback: /octahedron/pickup/feedback <feedback:float>
OSCdef(\octahedron_pickup_fb, { |msg|
    var fb = msg[1].asFloat;
    ~OCTAHEDRON_NODES !? { |nodes|
        nodes[\pickup] !? { |syn|
            syn.set(\feedback, fb.clip(0, 1));
        };
    };
}, "/octahedron/pickup/feedback");

// Slice trigger: /octahedron/slice <sliceIndex:int> <rate:float>
OSCdef(\octahedron_slice, { |msg|
    var idx = msg[1].asInteger;
    var rate = msg[2] !? _.asFloat ?? 1.0;
    // Trigger a one-shot slice playback
    ~OCTAHEDRON_NODES !? { |nodes|
        if(nodes[\sliceBuf].notNil) {
            Synth(\octahedron_slicer, [
                \outBus, nodes[\mainBus] ? 0,
                \bufnum, nodes[\sliceBuf],
                \sliceIndex, idx,
                \numSlices, nodes[\numSlices] ? 16,
                \rate, rate.clip(-4, 4),
                \gate, 1
            ], target: ~SC_GRP[\te]);
        };
    };
    ~VISUAL_CORTEX.target.sendMsg("/octahedron/slice/state", idx, rate);
}, "/octahedron/slice");

// Cue level: /octahedron/cue <cueLevel:float> <mainLevel:float>
OSCdef(\octahedron_cue_level, { |msg|
    var cueLevel = msg[1].asFloat;
    var mainLevel = msg[2] !? _.asFloat ?? 1.0;
    ~OCTAHEDRON_NODES !? { |nodes|
        nodes[\cue] !? { |syn|
            syn.set(\cueLevel, cueLevel.clip(0, 2), \mainLevel, mainLevel.clip(0, 2));
        };
    };
    ~VISUAL_CORTEX.target.sendMsg("/octahedron/cue/state", cueLevel, mainLevel);
}, "/octahedron/cue");

// Time stretch params: /octahedron/stretch <rate:float> <pitch:float> <grainSize:float>
OSCdef(\octahedron_stretch, { |msg|
    var rate = msg[1].asFloat;
    var pitch = msg[2] !? _.asFloat ?? 1.0;
    var grainSize = msg[3] !? _.asFloat ?? 0.1;
    ~OCTAHEDRON_NODES !? { |nodes|
        nodes[\stretch] !? { |syn|
            syn.set(\rate, rate.clip(0.01, 4), \pitch, pitch.clip(0.25, 4), \grainSize, grainSize.clip(0.01, 1));
        };
    };
    ~VISUAL_CORTEX.target.sendMsg("/octahedron/stretch/state", rate, pitch, grainSize);
}, "/octahedron/stretch");

// Arranger: /octahedron/arranger/add <pattern:int> <repeats:int> <condition:string>
OSCdef(\octahedron_arr_add, { |msg|
    var pattern = msg[1].asInteger;
    var repeats = msg[2] !? _.asInteger ?? 1;
    var condition = msg[3] !? _.asSymbol ?? \always;
    ~OCTAHEDRON_ARRANGER.addChain(pattern, repeats, condition);
}, "/octahedron/arranger/add");

// Arranger start: /octahedron/arranger/start
OSCdef(\octahedron_arr_start, {
    ~OCTAHEDRON_ARRANGER.start;
}, "/octahedron/arranger/start");

// Arranger stop: /octahedron/arranger/stop
OSCdef(\octahedron_arr_stop, {
    ~OCTAHEDRON_ARRANGER.stop;
}, "/octahedron/arranger/stop");

// Arranger reset: /octahedron/arranger/reset
OSCdef(\octahedron_arr_reset, {
    ~OCTAHEDRON_ARRANGER.reset;
}, "/octahedron/arranger/reset");

// Arranger clear: /octahedron/arranger/clear
OSCdef(\octahedron_arr_clear, {
    ~OCTAHEDRON_ARRANGER.clear;
}, "/octahedron/arranger/clear");

// Arranger advance (manual): /octahedron/arranger/advance
OSCdef(\octahedron_arr_advance, {
    var pat = ~OCTAHEDRON_ARRANGER.advance;
    if(pat.notNil) {
        ~VISUAL_CORTEX.target.sendMsg("/octahedron/arranger/pattern", pat);
    };
}, "/octahedron/arranger/advance");

// ==========================================
// Node holder for live instances
// ==========================================
~OCTAHEDRON_NODES = (
    crossfader: nil,
    pickup: nil,
    stretch: nil,
    cue: nil,
    sliceBuf: nil,
    mainBus: 0,
    cueBus: 2,
    numSlices: 16
);

"--- BRAHMA: OCTAHEDRON Octatrack Features Online (6 modules) ---".postln;
)
