/*
  Phase 9: SCRIPTORIUM — Audio Recording
  Multi-Track Recorder, Punch-In/Out, Bounce
*/

(
// ==========================================
// SYNTHDEF: Bus-to-Buffer Recorder
// ==========================================
SynthDef(\scriptorium_recorder, {
    |inBus=0, bufnum=0, record=0, preLevel=1.0, recLevel=1.0, loop=0|

    var in, run;

    in = In.ar(inBus, 2);

    // Gate recording on/off via record arg (> 0.5 = recording)
    run = record > 0.5;

    RecordBuf.ar(
        in,
        bufnum,
        recLevel: recLevel,
        preLevel: preLevel,
        run: run,
        loop: loop,
        doneAction: 0 // Do not free — managed by language
    );
}).add;

// Single-channel variant for mono tracks
SynthDef(\scriptorium_recorder_mono, {
    |inBus=0, bufnum=0, record=0, preLevel=1.0, recLevel=1.0, loop=0|

    var in, run;

    in = In.ar(inBus, 1);
    run = record > 0.5;

    RecordBuf.ar(
        in,
        bufnum,
        recLevel: recLevel,
        preLevel: preLevel,
        run: run,
        loop: loop,
        doneAction: 0
    );
}).add;

// ==========================================
// MULTI-TRACK RECORDER
// ==========================================
~SCRIPTORIUM_RECORDER = (
    tracks: IdentityDictionary.new,
    outputDir: Platform.recordingsDir,
    maxDuration: 300, // 5 minutes default max

    // ==========================================
    // TRACK MANAGEMENT
    // ==========================================

    // Arm a track for recording (allocates buffer, does not start)
    armTrack: { |self, name, inBus, numChannels=2|
        var buf = Buffer.alloc(s, s.sampleRate * self[\maxDuration], numChannels);
        self[\tracks][name.asSymbol] = (
            bus: inBus,
            buffer: buf,
            channels: numChannels,
            synth: nil,
            recording: false,
            armed: true,
            punchIn: false,
            startFrame: 0
        );
        "SCRIPTORIUM: Track '%' armed on bus % (% ch, % sec max)".format(
            name, inBus, numChannels, self[\maxDuration]).postln;
    },

    // Disarm and free a track
    freeTrack: { |self, name|
        var track = self[\tracks][name.asSymbol];
        if(track.notNil) {
            if(track[\recording]) { self.stopRecording(name) };
            track[\buffer].free;
            self[\tracks].removeAt(name.asSymbol);
            "SCRIPTORIUM: Track '%' freed".format(name).postln;
        };
    },

    // ==========================================
    // RECORDING CONTROL
    // ==========================================

    startRecording: { |self, name|
        var track = self[\tracks][name.asSymbol];
        if(track.notNil and: { track[\armed] }) {
            var synthName = if(track[\channels] == 1) {
                \scriptorium_recorder_mono
            } { \scriptorium_recorder };

            track[\synth] = Synth(synthName, [
                \inBus, track[\bus],
                \bufnum, track[\buffer].bufnum,
                \record, 1,
                \recLevel, 1.0,
                \preLevel, 0.0, // Clean record (no overdub)
                \loop, 0
            ]);
            track[\recording] = true;
            track[\startFrame] = 0;
            "SCRIPTORIUM: Recording '%' started".format(name).postln;
        } {
            "SCRIPTORIUM: Track '%' not armed or not found".format(name).warn;
        };
    },

    stopRecording: { |self, name|
        var track = self[\tracks][name.asSymbol];
        if(track.notNil and: { track[\recording] }) {
            track[\synth].set(\record, 0);
            track[\synth].free;
            track[\synth] = nil;
            track[\recording] = false;
            "SCRIPTORIUM: Recording '%' stopped".format(name).postln;
        };
    },

    // ==========================================
    // PUNCH IN/OUT (overdub on running track)
    // ==========================================

    punchIn: { |self, name, recLevel=1.0, preLevel=0.5|
        var track = self[\tracks][name.asSymbol];
        if(track.notNil and: { track[\recording] }) {
            track[\synth].set(\recLevel, recLevel, \preLevel, preLevel);
            track[\punchIn] = true;
            "SCRIPTORIUM: Punch-in on '%' (rec:%, pre:%)".format(
                name, recLevel, preLevel).postln;
        };
    },

    punchOut: { |self, name|
        var track = self[\tracks][name.asSymbol];
        if(track.notNil and: { track[\punchIn] }) {
            // Restore clean pass-through (no new recording, keep existing)
            track[\synth].set(\recLevel, 0.0, \preLevel, 1.0);
            track[\punchIn] = false;
            "SCRIPTORIUM: Punch-out on '%'".format(name).postln;
        };
    },

    // ==========================================
    // BATCH OPERATIONS
    // ==========================================

    startAll: { |self|
        self[\tracks].keysValuesDo({ |name, track|
            if(track[\armed]) { self.startRecording(name) };
        });
        "SCRIPTORIUM: All armed tracks recording".postln;
    },

    stopAll: { |self|
        self[\tracks].keysValuesDo({ |name, track|
            if(track[\recording]) { self.stopRecording(name) };
        });
        "SCRIPTORIUM: All tracks stopped".postln;
    },

    // ==========================================
    // FILE OUTPUT
    // ==========================================

    writeTrack: { |self, name, filename|
        var track = self[\tracks][name.asSymbol];
        if(track.notNil) {
            var path = self[\outputDir] +/+ (
                filename ? (name.asString ++ "_" ++ Date.getDate.stamp ++ ".wav")
            );
            track[\buffer].write(path, "wav", "float");
            "SCRIPTORIUM: Written '%' → %".format(name, path).postln;
        } {
            "SCRIPTORIUM: Track '%' not found".format(name).warn;
        };
    },

    writeAll: { |self, prefix|
        var stamp = Date.getDate.stamp;
        self[\tracks].keysValuesDo({ |name, track|
            var filename = (prefix ? "session") ++ "_" ++ name.asString ++ "_" ++ stamp ++ ".wav";
            self.writeTrack(name, filename);
        });
    },

    // Bounce: render a bus to file in real-time (convenience wrapper)
    bounceTrack: { |self, name, duration=10, filename|
        var track = self[\tracks][name.asSymbol];
        if(track.notNil) {
            self.startRecording(name);
            SystemClock.sched(duration, {
                self.stopRecording(name);
                self.writeTrack(name, filename);
                "SCRIPTORIUM: Bounce '%' complete (% sec)".format(name, duration).postln;
                nil;
            });
        };
    },

    // ==========================================
    // STATUS
    // ==========================================

    status: { |self|
        "SCRIPTORIUM RECORDER STATUS:".postln;
        self[\tracks].keysValuesDo({ |name, track|
            "  '%': armed=%, recording=%, bus=%, ch=%".format(
                name, track[\armed], track[\recording],
                track[\bus], track[\channels]).postln;
        });
    }
);

// ==========================================
// OSC RESPONDERS
// ==========================================

// /scriptorium/record/arm <name:string> <inBus:int> [numChannels:int]
OSCdef(\scriptorium_rec_arm, { |msg|
    var name = msg[1].asString;
    var inBus = msg[2].asInteger;
    var numCh = msg[3] !? _.asInteger ?? 2;
    ~SCRIPTORIUM_RECORDER.armTrack(name, inBus, numCh);
}, "/scriptorium/record/arm");

// /scriptorium/record/start <name:string>
OSCdef(\scriptorium_rec_start, { |msg|
    ~SCRIPTORIUM_RECORDER.startRecording(msg[1].asString);
}, "/scriptorium/record/start");

// /scriptorium/record/stop <name:string>
OSCdef(\scriptorium_rec_stop, { |msg|
    ~SCRIPTORIUM_RECORDER.stopRecording(msg[1].asString);
}, "/scriptorium/record/stop");

// /scriptorium/record/write <name:string> [filename:string]
OSCdef(\scriptorium_rec_write, { |msg|
    var name = msg[1].asString;
    var filename = msg[2] !? _.asString;
    ~SCRIPTORIUM_RECORDER.writeTrack(name, filename);
}, "/scriptorium/record/write");

// /scriptorium/record/startAll
OSCdef(\scriptorium_rec_start_all, {
    ~SCRIPTORIUM_RECORDER.startAll;
}, "/scriptorium/record/startAll");

// /scriptorium/record/stopAll
OSCdef(\scriptorium_rec_stop_all, {
    ~SCRIPTORIUM_RECORDER.stopAll;
}, "/scriptorium/record/stopAll");

// /scriptorium/record/writeAll [prefix:string]
OSCdef(\scriptorium_rec_write_all, { |msg|
    var prefix = msg[1] !? _.asString;
    ~SCRIPTORIUM_RECORDER.writeAll(prefix);
}, "/scriptorium/record/writeAll");

// /scriptorium/record/punchIn <name:string> [recLevel:float] [preLevel:float]
OSCdef(\scriptorium_rec_punch_in, { |msg|
    var name = msg[1].asString;
    var recLevel = msg[2] !? _.asFloat ?? 1.0;
    var preLevel = msg[3] !? _.asFloat ?? 0.5;
    ~SCRIPTORIUM_RECORDER.punchIn(name, recLevel, preLevel);
}, "/scriptorium/record/punchIn");

// /scriptorium/record/punchOut <name:string>
OSCdef(\scriptorium_rec_punch_out, { |msg|
    ~SCRIPTORIUM_RECORDER.punchOut(msg[1].asString);
}, "/scriptorium/record/punchOut");

// /scriptorium/record/bounce <name:string> <duration:float> [filename:string]
OSCdef(\scriptorium_rec_bounce, { |msg|
    var name = msg[1].asString;
    var duration = msg[2] !? _.asFloat ?? 10;
    var filename = msg[3] !? _.asString;
    ~SCRIPTORIUM_RECORDER.bounceTrack(name, duration, filename);
}, "/scriptorium/record/bounce");

// /scriptorium/record/free <name:string>
OSCdef(\scriptorium_rec_free, { |msg|
    ~SCRIPTORIUM_RECORDER.freeTrack(msg[1].asString);
}, "/scriptorium/record/free");

// /scriptorium/record/status
OSCdef(\scriptorium_rec_status, {
    ~SCRIPTORIUM_RECORDER.status;
}, "/scriptorium/record/status");

"--- BRAHMA: SCRIPTORIUM Recording Online ---".postln;
)
