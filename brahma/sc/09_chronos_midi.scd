/*
  Phase 1: CHRONOS MIDI I/O
  Route tracks to external MIDI, receive MIDI into tracks,
  MIDI clock sync integration
*/

(
~CHRONOS_MIDI = (

    // MIDI output routing per track
    // trackMidiOut: Dictionary trackIdx -> (channel, port)
    trackMidiOut: Dictionary.new,

    // MIDI output object (initialized when needed)
    midiOut: nil,

    // ==========================================
    // MIDI OUTPUT INIT
    // ==========================================
    initOutput: { |self|
        if(MIDIClient.initialized.not) { MIDIClient.init };
        if(MIDIClient.destinations.size > 0) {
            self[\midiOut] = MIDIOut(0, MIDIClient.destinations[0].uid);
            "CHRONOS MIDI: Output initialized → %".format(
                MIDIClient.destinations[0].name).postln;
        } {
            "CHRONOS MIDI: No MIDI output destinations found".warn;
        };
    },

    // ==========================================
    // TRACK MIDI ROUTING
    // ==========================================
    routeTrackToMIDI: { |self, trackIdx, channel=0, port=0|
        self[\trackMidiOut].put(trackIdx, (channel: channel, port: port));
        "CHRONOS MIDI: Track % → MIDI ch % port %".format(trackIdx, channel, port).postln;
    },

    unrouteTrackMIDI: { |self, trackIdx|
        self[\trackMidiOut].removeAt(trackIdx);
        "CHRONOS MIDI: Track % MIDI output removed".format(trackIdx).postln;
    },

    // Called by CHRONOS_TRACKS.triggerStep for MIDI-routed tracks
    sendNoteForStep: { |self, trackIdx, stepData|
        var routing = self[\trackMidiOut][trackIdx];
        if(routing.notNil and: { self[\midiOut].notNil }) {
            var ch = routing[\channel];
            var note = stepData[\note] + stepData[\transpose];
            var vel = stepData[\velocity];
            var durTicks = stepData[\length];
            var durSec = durTicks * 60 / ~CHRONOS[\tempo] / 96;

            self[\midiOut].noteOn(ch, note.clip(0, 127), vel.clip(0, 127));

            // Schedule note off
            SystemClock.sched(durSec, {
                self[\midiOut].noteOff(ch, note.clip(0, 127), 0);
                nil;
            });
        };
    },

    // ==========================================
    // MIDI CLOCK SYNC
    // ==========================================
    // Sync Chronos tempo to external MIDI clock
    syncToExternalClock: { |self|
        ~BRAHMA_MIDI[\externalSync] = true;
        "CHRONOS MIDI: Syncing to external MIDI clock".postln;
    },

    // Send MIDI clock from Chronos
    startClockSend: { |self|
        if(self[\midiOut].notNil) {
            self[\midiOut].start;
            self[\clockSendRoutine] = Routine({
                loop {
                    self[\midiOut].midiClock;
                    (60 / ~CHRONOS[\tempo] / 24).wait; // 24 PPQN
                };
            }).play;
            "CHRONOS MIDI: Clock send started at % BPM".format(~CHRONOS[\tempo]).postln;
        };
    },

    stopClockSend: { |self|
        if(self[\clockSendRoutine].notNil) {
            self[\clockSendRoutine].stop;
            self[\clockSendRoutine] = nil;
        };
        if(self[\midiOut].notNil) {
            self[\midiOut].stop;
        };
        "CHRONOS MIDI: Clock send stopped".postln;
    },

    // ==========================================
    // MIDI INPUT RECORDING
    // ==========================================
    // Record incoming MIDI notes into a track's pattern
    armTrackForRecording: { |self, trackIdx|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            track[\recording] = true;
            "CHRONOS MIDI: Track % armed for recording".format(trackIdx).postln;
        };
    },

    disarmTrackRecording: { |self, trackIdx|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            track[\recording] = false;
            "CHRONOS MIDI: Track % disarmed".format(trackIdx).postln;
        };
    },

    // Called on MIDI noteOn — records to armed tracks
    recordNote: { |self, note, velocity, channel|
        ~CHRONOS[\tracks].do({ |track, idx|
            if(track.notNil and: { track[\recording] == true } and: { ~CHRONOS[\playing] }) {
                var step = track[\currentStep] % track[\numSteps];
                track[\pattern][step][\active] = true;
                track[\pattern][step][\note] = note;
                track[\pattern][step][\velocity] = velocity;
            };
        });
    }
);

// ==========================================
// OSC RESPONDERS
// ==========================================
OSCdef(\chronos_midi_route, { |msg|
    ~CHRONOS_MIDI.routeTrackToMIDI(msg[1].asInteger,
        msg[2] !? _.asInteger ?? 0,
        msg[3] !? _.asInteger ?? 0);
}, "/chronos/midi/route");

OSCdef(\chronos_midi_unroute, { |msg|
    ~CHRONOS_MIDI.unrouteTrackMIDI(msg[1].asInteger);
}, "/chronos/midi/unroute");

OSCdef(\chronos_midi_clock_send, { |msg|
    if(msg[1].asInteger > 0) {
        ~CHRONOS_MIDI.startClockSend;
    } {
        ~CHRONOS_MIDI.stopClockSend;
    };
}, "/chronos/midi/clock/send");

OSCdef(\chronos_midi_clock_sync, {
    ~CHRONOS_MIDI.syncToExternalClock;
}, "/chronos/midi/clock/sync");

OSCdef(\chronos_midi_arm, { |msg|
    ~CHRONOS_MIDI.armTrackForRecording(msg[1].asInteger);
}, "/chronos/midi/arm");

OSCdef(\chronos_midi_disarm, { |msg|
    ~CHRONOS_MIDI.disarmTrackRecording(msg[1].asInteger);
}, "/chronos/midi/disarm");

OSCdef(\chronos_midi_init_out, {
    ~CHRONOS_MIDI.initOutput;
}, "/chronos/midi/init");

// Hook MIDI recording into the MIDI input system
MIDIdef.noteOn(\chronos_record, { |vel, note, ch, src|
    ~CHRONOS_MIDI.recordNote(note, vel, ch);
});

"--- BRAHMA: CHRONOS MIDI I/O Online ---".postln;
)
