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
     gate=1, rate=1.0, startPos=0, amp=1.0|

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

    Out.ar(outBus, play * env * amp);
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
~octahedron_arranger = (
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
    ~octahedron_nodes !? { |nodes|
        nodes[\crossfader] !? { |syn|
            syn.set(\xfade, xfade.clip(0, 1), \curve, curve.clip(0, 1));
        };
    };
    ~visual_cortex.target.sendMsg("/octahedron/crossfade/state", xfade, curve);
}, "/octahedron/crossfade");

// Pickup machine record control: /octahedron/record <record:int> <overdub:int>
OSCdef(\octahedron_record, { |msg|
    var record = msg[1].asInteger;
    var overdub = msg[2] !? _.asInteger ?? 0;
    ~octahedron_nodes !? { |nodes|
        nodes[\pickup] !? { |syn|
            syn.set(\record, record, \overdub, overdub);
        };
    };
    ~visual_cortex.target.sendMsg("/octahedron/record/state", record, overdub);
}, "/octahedron/record");

// Pickup feedback: /octahedron/pickup/feedback <feedback:float>
OSCdef(\octahedron_pickup_fb, { |msg|
    var fb = msg[1].asFloat;
    ~octahedron_nodes !? { |nodes|
        nodes[\pickup] !? { |syn|
            syn.set(\feedback, fb.clip(0, 1));
        };
    };
}, "/octahedron/pickup/feedback");

// Slice trigger: /octahedron/slice <sliceIndex:int> <rate:float>
OSCdef(\octahedron_slice, { |msg|
    var idx = msg[1].asInteger;
    var rate = msg[2] !? _.asFloat ?? 1.0;
    var syn;
    // Trigger a one-shot slice playback
    ~octahedron_nodes !? { |nodes|
        if(nodes[\sliceBuf].notNil) {
            syn = Synth(\octahedron_slicer, [
                \outBus, nodes[\mainBus] ? 0,
                \bufnum, nodes[\sliceBuf],
                \sliceIndex, idx,
                \numSlices, nodes[\numSlices] ? 16,
                \rate, rate.clip(-4, 4),
                \gate, 1
            ], target: ~sc_grp[\te]);
            // Track the voice so /octahedron/stop can release it: a slice
            // synth holds its ASR gate until gated off (#95).
            nodes[\sliceVoices].add(syn);
        };
    };
    ~visual_cortex.target.sendMsg("/octahedron/slice/state", idx, rate);
}, "/octahedron/slice");

// Cue level: /octahedron/cue <cueLevel:float> <mainLevel:float>
OSCdef(\octahedron_cue_level, { |msg|
    var cueLevel = msg[1].asFloat;
    var mainLevel = msg[2] !? _.asFloat ?? 1.0;
    ~octahedron_nodes !? { |nodes|
        nodes[\cue] !? { |syn|
            syn.set(\cueLevel, cueLevel.clip(0, 2), \mainLevel, mainLevel.clip(0, 2));
        };
    };
    ~visual_cortex.target.sendMsg("/octahedron/cue/state", cueLevel, mainLevel);
}, "/octahedron/cue");

// Time stretch params: /octahedron/stretch <rate:float> <pitch:float> <grainSize:float>
OSCdef(\octahedron_stretch, { |msg|
    var rate = msg[1].asFloat;
    var pitch = msg[2] !? _.asFloat ?? 1.0;
    var grainSize = msg[3] !? _.asFloat ?? 0.1;
    ~octahedron_nodes !? { |nodes|
        nodes[\stretch] !? { |syn|
            syn.set(\rate, rate.clip(0.01, 4), \pitch, pitch.clip(0.25, 4), \grainSize, grainSize.clip(0.01, 1));
        };
    };
    ~visual_cortex.target.sendMsg("/octahedron/stretch/state", rate, pitch, grainSize);
}, "/octahedron/stretch");

// Arranger: /octahedron/arranger/add <pattern:int> <repeats:int> <condition:string>
OSCdef(\octahedron_arr_add, { |msg|
    var pattern = msg[1].asInteger;
    var repeats = msg[2] !? _.asInteger ?? 1;
    var condition = msg[3] !? _.asSymbol ?? \always;
    ~octahedron_arranger.addChain(pattern, repeats, condition);
}, "/octahedron/arranger/add");

// Arranger start: /octahedron/arranger/start
OSCdef(\octahedron_arr_start, {
    ~octahedron_arranger.start;
}, "/octahedron/arranger/start");

// Arranger stop: /octahedron/arranger/stop
OSCdef(\octahedron_arr_stop, {
    ~octahedron_arranger.stop;
}, "/octahedron/arranger/stop");

// Arranger reset: /octahedron/arranger/reset
OSCdef(\octahedron_arr_reset, {
    ~octahedron_arranger.reset;
}, "/octahedron/arranger/reset");

// Arranger clear: /octahedron/arranger/clear
OSCdef(\octahedron_arr_clear, {
    ~octahedron_arranger.clear;
}, "/octahedron/arranger/clear");

// Arranger advance (manual): /octahedron/arranger/advance
OSCdef(\octahedron_arr_advance, {
    var pat = ~octahedron_arranger.advance;
    if(pat.notNil) {
        ~visual_cortex.target.sendMsg("/octahedron/arranger/pattern", pat);
    };
}, "/octahedron/arranger/advance");

// ==========================================
// INSTRUMENT NOTES + SAMPLE LOAD — song sampling (#95, plan steps 1-2)
// ==========================================
// The browser instrument sends /brahma/instrument/note for every pattern
// event when the OSC engine is selected (brahma/web/public/instrument/
// instrument.js, OscAdapter), but no receiver existed: the notes went
// nowhere. And the slicer above could never sound: sliceBuf was nil with
// no load path. This section closes both gaps.
//
// Placement note: the receiver lives here, not in 16_engine_responders.scd,
// because the slicer and sliceBuf live here; the generic voice manager in
// 16 owns engine voices, which instrument notes deliberately bypass —
// they trigger slices, not engine voices.
//
// Trust boundary: these addresses arrive over the browser WebSocket bridge,
// which forwards /brahma/ only from authenticated human sessions
// (brahma/web/lib/session.js, handleLegacyOsc) at a rate-limited 200/s.
// Buffer.read only reads: the load path never writes the source file.
//
// Step 3 (plan step 3): the note contract carries the pattern cell's chosen
// chop as an optional 5th arg. The browser sends it only for sample events;
// plain notes still derive their slice from pitch. The slice selects within
// the one bound buffer — the browser's sampleId stays local, so the chop a
// cell plays is the chop of whatever file /octahedron/load bound last.

// Release every tracked slice voice. Returns the count released.
// A slice synth holds its ASR gate until gated off, so stop must be
// explicit — ending the Routine or freeing the buffer does not end it.
~octahedron_sliceStopAll = { |nodes|
    var count = 0;
    nodes[\sliceVoices].do({ |syn|
        if(syn.notNil) { syn.set(\gate, 0); count = count + 1 };
    });
    nodes[\sliceVoices] = List.new;
    count
};

// Release one tracked slice voice, if it is still tracked. A later stop
// or load clears the list first, so a stale auto-release timer must never
// gate off a newer voice (same guard shape as /brahma/live/play).
~octahedron_sliceReleaseVoice = { |nodes, syn|
    if(nodes[\sliceVoices].includes(syn)) {
        nodes[\sliceVoices].remove(syn);
        syn.set(\gate, 0);
    };
};

// Trigger one slice voice on the bound buffer and auto-release it after
// <dur> seconds. Shared by /brahma/instrument/note (plan steps 1-3) and
// the Golem sequencer's slice tracks (plan step 4): one voice path, so
// stop and release semantics stay identical whichever side started the
// voice. Returns the Synth, or nil when no buffer is bound (the caller
// acks that case itself). Callers pass gain 0..1, rate -4..4, dur > 0.
// <outBus> lets the sequencer route the voice through the track's audio
// bus and its FX chain; the note receiver passes the main bus.
// <rate> is playback rate only: how fast the chop plays, never an
// independent pitch/time stretch — that needs the octahedron_timestretch
// voice (plan step 5), never a rate relabel.
~octahedron_playSlice = { |nodes, sliceIndex, rate, gain, dur, outBus|
    var buf, syn, task;
    buf = nodes[\sliceBuf];
    if(buf.isNil) { nil } {
        syn = Synth(\octahedron_slicer, [
            \outBus, outBus,
            \bufnum, buf,
            \sliceIndex, sliceIndex,
            \numSlices, nodes[\numSlices] ? 16,
            \rate, rate.clip(-4, 4),
            \amp, gain,
            \gate, 1
        ], target: ~sc_grp[\te]);
        nodes[\sliceVoices].add(syn);
        task = Routine({
            dur.wait;
            ~octahedron_sliceReleaseVoice.(nodes, syn);
        });
        task.play(SystemClock);
        syn
    };
};

// Instrument note: /brahma/instrument/note <track:string> <note:int> <gain:float> <dur:float> [slice:int]
// Maps the note to a slice and triggers the slicer on the bound buffer,
// auto-releasing after <dur> so pattern events never leave hanging notes.
// The optional 5th arg is the pattern cell's chosen chop (plan step 3):
// a sample event carries its slice explicitly and sounds exactly that chop;
// a plain note event omits it and keeps the pitch-derived slice
// (note % numSlices). An out-of-range slice is a typed ack, never a clip —
// silently playing a different chop than the pattern asked for would hide
// a broken binding. Replies on /brahma/instrument/note/ack
// <track> <note> <ok:int> <sliceIndex|message>: an open socket is not an
// ack — the browser learns whether the engine actually sounded the note,
// or that no sample is bound yet.
OSCdef(\instrument_note, { |msg|
    var track, note, gain, dur, slice, nodes, buf, sliceIndex;
    if(msg.size < 5) {
        ~visual_cortex.target.sendMsg("/brahma/instrument/note/ack",
            msg[1] ? "?", 0, 0, "bad_args: note needs <track> <note> <gain> <dur>");
    } {
        track = msg[1].asString;
        note = msg[2].asInteger;
        gain = msg[3].asFloat.clip(0, 1);
        dur = msg[4].asFloat.clip(0.01, 30);
        slice = if(msg.size > 5) { msg[5].asInteger } { nil };
        if(note < 0 or: { note > 127 }) {
            ~visual_cortex.target.sendMsg("/brahma/instrument/note/ack",
                track, note, 0, "bad_args: note out of range 0..127");
        } {
            ~octahedron_nodes !? { |nds|
                nodes = nds;
                buf = nodes[\sliceBuf];
                if(buf.isNil) {
                    ~visual_cortex.target.sendMsg("/brahma/instrument/note/ack",
                        track, note, 0, "no buffer loaded: send /octahedron/load first");
                } {
                    if(slice.notNil and: { slice < 0 or: { slice >= (nodes[\numSlices] ? 16) } }) {
                        ~visual_cortex.target.sendMsg("/brahma/instrument/note/ack",
                            track, note, 0, "bad_args: slice out of range 0..%".format((nodes[\numSlices] ? 16) - 1));
                    } {
                        sliceIndex = slice ? (note % (nodes[\numSlices] ? 16));
                        ~octahedron_playSlice.(nodes, sliceIndex, 1.0, gain, dur, nodes[\mainBus] ? 0);
                        ~visual_cortex.target.sendMsg("/brahma/instrument/note/ack",
                            track, note, 1, sliceIndex);
                    };
                };
            };
        };
    };
}, "/brahma/instrument/note");

// Sample load: /octahedron/load <path:string> [numSlices:int]
// Binds a real audio file to the slicer (sliceBuf), so
// /brahma/instrument/note and /octahedron/slice can sound it. The path is
// validated before any server call (File.exists, then SoundFile.openRead
// for the header): a missing or unreadable file gets an error ack, never
// a silent no-op. Replacing a bound buffer first gates off every sounding
// slice voice, then frees the old buffer after the 5ms release tail, so
// the previous sample never keeps sounding; the source file itself is
// only ever read. A later load supersedes an in-flight one: its action
// frees its buffer instead of binding a stale one (loadToken guard).
// Replies on /octahedron/load/state — success:
//   <1> <path> <bufnum> <numFrames> <numChannels> <numSlices> <voicesFreed>
// failure: <0> <path> <message>.
OSCdef(\octahedron_load, { |msg|
    var path, slices, token, nodes, sf;
    if(msg.size < 2 or: { msg[1].asString.size == 0 }) {
        ~visual_cortex.target.sendMsg("/octahedron/load/state",
            0, "", "bad_args: load needs <path> [numSlices]");
    } {
        path = msg[1].asString;
        slices = if(msg.size > 2) { msg[2].asInteger.clip(1, 128) } { nil };
        if(File.exists(path).not) {
            ~visual_cortex.target.sendMsg("/octahedron/load/state",
                0, path, "no such file");
        } {
            sf = SoundFile.openRead(path);
            if(sf.isNil) {
                ~visual_cortex.target.sendMsg("/octahedron/load/state",
                    0, path, "not a readable audio file");
            } {
                sf.close;
                ~octahedron_nodes !? { |nds|
                    nodes = nds;
                    nodes[\loadToken] = nodes[\loadToken] + 1;
                    token = nodes[\loadToken];
                    Buffer.read(s, path, action: { |buf|
                        var oldBuf, oldVoices;
                        if(token == nodes[\loadToken]) {
                            if(buf.numFrames == 0) {
                                buf.free;
                                ~visual_cortex.target.sendMsg("/octahedron/load/state",
                                    0, path, "not a readable audio file");
                            } {
                                if(slices.notNil) { nodes[\numSlices] = slices };
                                oldBuf = nodes[\sliceBuf];
                                oldVoices = ~octahedron_sliceStopAll.(nodes);
                                nodes[\sliceBuf] = buf;
                                if(oldBuf.notNil) {
                                    Routine({ 0.1.wait; oldBuf.free; }).play(SystemClock);
                                };
                                ~visual_cortex.target.sendMsg("/octahedron/load/state",
                                    1, path, buf.bufnum, buf.numFrames, buf.numChannels,
                                    nodes[\numSlices], oldVoices);
                            };
                        } {
                            buf.free;
                        };
                    });
                };
            };
        };
    };
}, "/octahedron/load");

// Slice stop: /octahedron/stop — gates off every sounding slice voice.
// Replies on /octahedron/stop/state <freed:int>. Stop never frees the
// bound buffer: a later note on the same buffer must still sound.
OSCdef(\octahedron_stop, {
    var freed = 0;
    ~octahedron_nodes !? { |nodes|
        freed = ~octahedron_sliceStopAll.(nodes);
    };
    ~visual_cortex.target.sendMsg("/octahedron/stop/state", freed);
}, "/octahedron/stop");

// ==========================================
// Node holder for live instances
// ==========================================
~octahedron_nodes = (
    crossfader: nil,
    pickup: nil,
    stretch: nil,
    cue: nil,
    sliceBuf: nil,
    sliceVoices: List.new,
    loadToken: 0,
    mainBus: 0,
    cueBus: 2,
    numSlices: 16
);

"--- BRAHMA: OCTAHEDRON Octatrack Features Online (6 modules) ---".postln;

// ==========================================
// PATCH BAY REGISTRATION — Octatrack Modules
// ==========================================
[
    [\octahedron_crossfader, [
        [\xfade, "Crossfade position"], [\curve, "Crossfade curve"]
    ]],
    [\octahedron_pickup, [
        [\record, "Record toggle"], [\overdub, "Overdub toggle"],
        [\feedback, "Overdub feedback"], [\level, "Playback level"]
    ]],
    [\octahedron_timestretch, [
        [\rate, "Time stretch rate"], [\pitch, "Pitch shift"],
        [\grainSize, "Grain size"], [\overlap, "Grain overlap"]
    ]],
    [\octahedron_slicer, [
        [\sliceIndex, "Slice index"], [\rate, "Playback rate"]
    ]],
    [\octahedron_cue, [
        [\cueLevel, "Cue level"], [\mainLevel, "Main level"]
    ]]
].do({ |moduleSpec|
    var synthName = moduleSpec[0];
    var params = moduleSpec[1];
    params.do({ |p|
        ~patch_bay.registerDestination(
            (synthName.asString ++ "_" ++ p[0].asString).asSymbol,
            p[0], synthName.asString ++ " " ++ p[1]
        );
    });
});

// --- MODULE REGISTRY REGISTRATION ---
if(~module_registry.notNil) {
    // OCTAHEDRON CROSSFADER — Scene A/B blending
    ~module_registry.register(\octahedron_crossfader, \elektron, \octahedron_crossfader, [
        (\name: \inBusA, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Scene A input bus"),
        (\name: \inBusB, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Scene B input bus"),
        (\name: \xfade, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Crossfade position (0=A, 1=B)"),
        (\name: \curve, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Crossfade curve (0=equal power, 1=linear)"),
    ], ~sc_grp[\te], "Scene A/B crossfader with equal-power and linear curves");

    // OCTAHEDRON PICKUP — Live loop recorder/overdub
    ~module_registry.register(\octahedron_pickup, \elektron, \octahedron_pickup, [
        (\name: \inBus, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Audio input bus"),
        (\name: \bufnum, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Recording buffer number"),
        (\name: \record, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Record toggle (>0.5 = armed)"),
        (\name: \overdub, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Overdub toggle (>0.5 = active)"),
        (\name: \multiply, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Multiply mode"),
        (\name: \level, \default: 1.0, \min: 0, \max: 2, \units: "", \desc: "Playback level"),
        (\name: \feedback, \default: 0.8, \min: 0, \max: 1, \units: "", \desc: "Overdub feedback (content preservation)"),
    ], ~sc_grp[\te], "Live loop recorder with overdub and feedback control");

    // OCTAHEDRON TIMESTRETCH — Granular phase vocoder
    ~module_registry.register(\octahedron_timestretch, \elektron, \octahedron_timestretch, [
        (\name: \inBus, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Audio input bus"),
        (\name: \bufnum, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Source buffer number"),
        (\name: \rate, \default: 1.0, \min: 0.01, \max: 4.0, \units: "x", \desc: "Time stretch rate"),
        (\name: \pitch, \default: 1.0, \min: 0.25, \max: 4.0, \units: "x", \desc: "Pitch shift ratio"),
        (\name: \grainSize, \default: 0.1, \min: 0.01, \max: 1.0, \units: "s", \desc: "Grain duration"),
        (\name: \overlap, \default: 4, \min: 1, \max: 16, \units: "", \desc: "Grain overlap factor"),
    ], ~sc_grp[\te], "Granular time stretch with independent rate and pitch control");

    // OCTAHEDRON SLICER — Sample slice playback
    ~module_registry.register(\octahedron_slicer, \elektron, \octahedron_slicer, [
        (\name: \bufnum, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Source buffer number"),
        (\name: \sliceIndex, \default: 0, \min: 0, \max: 127, \units: "", \desc: "Slice index"),
        (\name: \numSlices, \default: 16, \min: 1, \max: 128, \units: "", \desc: "Total number of slices"),
        (\name: \rate, \default: 1.0, \min: -4, \max: 4, \units: "x", \desc: "Playback rate"),
        (\name: \amp, \default: 1.0, \min: 0, \max: 2, \units: "", \desc: "Slice voice level (instrument note gain)"),
        (\name: \startPos, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Start position (normalized, if sliceIndex=0)"),
    ], ~sc_grp[\te], "Sample slicer with indexed slice playback");

    // OCTAHEDRON CUE — Dual-destination router
    ~module_registry.register(\octahedron_cue, \elektron, \octahedron_cue, [
        (\name: \inBus, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Stereo input bus"),
        (\name: \cueBus, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Cue/headphone output bus"),
        (\name: \mainBus, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "Main output bus"),
        (\name: \cueLevel, \default: 1.0, \min: 0, \max: 2, \units: "", \desc: "Cue output level"),
        (\name: \mainLevel, \default: 1.0, \min: 0, \max: 2, \units: "", \desc: "Main output level"),
    ], ~sc_grp[\te], "DJ-style dual-destination cue/main router");
};
)
