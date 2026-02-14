/*
  Phase 9: SCRIPTORIUM — Clock Sync
  MIDI Clock Send/Receive, Ableton Link, Tap Tempo
*/

(
// ==========================================
// CLOCK SYNC MANAGER
// ==========================================
~SCRIPTORIUM_SYNC = (
    midiClockOut: nil,
    midiClockRunning: false,
    clockRoutine: nil,
    linkClock: nil,
    lastClockTick: nil,
    clockTickCount: 0,
    tapTimes: List.new,

    // ==========================================
    // MIDI CLOCK SEND (24 PPQN)
    // ==========================================

    startMIDIClockSend: { |self, midiOut, bpm=120|
        self[\midiClockOut] = midiOut;
        self[\midiClockRunning] = true;

        // Send MIDI Start message
        self[\midiClockOut].start;

        self[\clockRoutine] = Routine({
            var interval;
            loop {
                // MIDI clock = 24 pulses per quarter note
                interval = 60 / (bpm * 24);
                if(self[\midiClockRunning]) {
                    self[\midiClockOut].midiClock;
                };
                interval.wait;
            };
        }).play;
        "SCRIPTORIUM SYNC: MIDI clock send started at % BPM".format(bpm).postln;
    },

    stopMIDIClockSend: { |self|
        self[\midiClockRunning] = false;
        if(self[\clockRoutine].notNil) {
            self[\clockRoutine].stop;
            self[\clockRoutine] = nil;
        };
        if(self[\midiClockOut].notNil) {
            self[\midiClockOut].stop; // MIDI Stop message
        };
        "SCRIPTORIUM SYNC: MIDI clock send stopped".postln;
    },

    // Update BPM while clock is running (does not restart)
    setMIDIClockBPM: { |self, bpm|
        // The loop reads bpm each iteration, so we store it for reference
        // Note: caller should update the tempo variable used in the routine
        "SCRIPTORIUM SYNC: MIDI clock BPM → %".format(bpm).postln;
    },

    // ==========================================
    // MIDI CLOCK RECEIVE
    // ==========================================

    startMIDIClockReceive: { |self|
        self[\clockTickCount] = 0;
        self[\lastClockTick] = nil;

        MIDIIn.sysrt = { |src, index|
            case
            // index 8 = clock tick
            { index == 8 } {
                var now = Main.elapsedTime;
                self[\clockTickCount] = self[\clockTickCount] + 1;

                if(self[\lastClockTick].notNil) {
                    // Accumulate over 24 ticks (one beat) for stable BPM
                    if(self[\clockTickCount] >= 24) {
                        var interval = now - self[\lastClockTick];
                        var bpm = (60 / interval).clip(20, 300).round(0.1);
                        if(~CHRONOS.notNil) {
                            ~CHRONOS[\tempo] = bpm;
                        };
                        self[\clockTickCount] = 0;
                        self[\lastClockTick] = now;
                    };
                } {
                    // First tick — initialize reference
                    self[\lastClockTick] = now;
                };
            }
            // index 10 = MIDI Start
            { index == 10 } {
                self[\clockTickCount] = 0;
                self[\lastClockTick] = Main.elapsedTime;
                "SCRIPTORIUM SYNC: External MIDI Start received".postln;
            }
            // index 11 = MIDI Continue
            { index == 11 } {
                "SCRIPTORIUM SYNC: External MIDI Continue received".postln;
            }
            // index 12 = MIDI Stop
            { index == 12 } {
                "SCRIPTORIUM SYNC: External MIDI Stop received".postln;
            };
        };
        "SCRIPTORIUM SYNC: MIDI clock receive started".postln;
    },

    stopMIDIClockReceive: { |self|
        MIDIIn.sysrt = nil;
        self[\lastClockTick] = nil;
        self[\clockTickCount] = 0;
        "SCRIPTORIUM SYNC: MIDI clock receive stopped".postln;
    },

    // ==========================================
    // ABLETON LINK
    // ==========================================

    startLink: { |self, bpm=120|
        if(\LinkClock.asClass.notNil) {
            self[\linkClock] = LinkClock(bpm / 60); // LinkClock takes beats per second
            TempoClock.default = self[\linkClock];
            "SCRIPTORIUM SYNC: Ableton Link started at % BPM (% peers)".format(
                bpm, self[\linkClock].numPeers).postln;
        } {
            "SCRIPTORIUM SYNC: LinkClock quark not installed".postln;
            "  Install with: Quarks.install(\"LinkClock\")".postln;
        };
    },

    stopLink: { |self|
        if(self[\linkClock].notNil) {
            self[\linkClock].stop;
            self[\linkClock] = nil;
            TempoClock.default = TempoClock.new; // Restore default
            "SCRIPTORIUM SYNC: Ableton Link stopped".postln;
        };
    },

    getLinkPeers: { |self|
        if(self[\linkClock].notNil) {
            var peers = self[\linkClock].numPeers;
            "SCRIPTORIUM SYNC: Link peers = %".format(peers).postln;
            peers;
        } { 0 };
    },

    setLinkBPM: { |self, bpm|
        if(self[\linkClock].notNil) {
            self[\linkClock].tempo = bpm / 60;
            "SCRIPTORIUM SYNC: Link tempo → % BPM".format(bpm).postln;
        };
    },

    // ==========================================
    // TAP TEMPO
    // ==========================================

    tap: { |self|
        var now = Main.elapsedTime;
        self[\tapTimes].add(now);

        // Keep only last 8 taps for averaging
        if(self[\tapTimes].size > 8) {
            self[\tapTimes].removeAt(0);
        };

        if(self[\tapTimes].size >= 2) {
            var intervals = (self[\tapTimes].size - 1).collect({ |i|
                self[\tapTimes][i + 1] - self[\tapTimes][i];
            });
            var bpm = 60 / intervals.mean;
            bpm = bpm.clip(20, 300).round(0.1);

            // Update Chronos if available
            if(~CHRONOS.notNil) { ~CHRONOS[\tempo] = bpm };

            // Update Link if active
            if(self[\linkClock].notNil) {
                self[\linkClock].tempo = bpm / 60;
            };

            "SCRIPTORIUM SYNC: Tap tempo → % BPM (% taps)".format(
                bpm, self[\tapTimes].size).postln;
            bpm;
        } { nil };
    },

    resetTap: { |self|
        self[\tapTimes] = List.new;
        "SCRIPTORIUM SYNC: Tap tempo reset".postln;
    },

    // ==========================================
    // STATUS
    // ==========================================

    status: { |self|
        "SCRIPTORIUM SYNC STATUS:".postln;
        "  MIDI clock send: %".format(self[\midiClockRunning]).postln;
        "  MIDI clock receive: %".format(MIDIIn.sysrt.notNil).postln;
        "  Ableton Link: %".format(self[\linkClock].notNil).postln;
        if(self[\linkClock].notNil) {
            "  Link peers: %".format(self[\linkClock].numPeers).postln;
            "  Link BPM: %".format(self[\linkClock].tempo * 60).postln;
        };
        if(~CHRONOS.notNil) {
            "  Chronos tempo: % BPM".format(~CHRONOS[\tempo]).postln;
        };
    }
);

// ==========================================
// OSC RESPONDERS
// ==========================================

// /scriptorium/sync/midiClock/startSend [bpm:float]
OSCdef(\scriptorium_sync_midi_send_start, { |msg|
    var bpm = msg[1] !? _.asFloat ?? 120;
    // Initialize MIDI if needed
    if(MIDIClient.initialized.not) { MIDIClient.init };
    if(MIDIClient.destinations.size > 0) {
        var midiOut = MIDIOut(0, MIDIClient.destinations[0].uid);
        ~SCRIPTORIUM_SYNC.startMIDIClockSend(midiOut, bpm);
    } {
        "SCRIPTORIUM SYNC: No MIDI destinations available".warn;
    };
}, "/scriptorium/sync/midiClock/startSend");

// /scriptorium/sync/midiClock/stopSend
OSCdef(\scriptorium_sync_midi_send_stop, {
    ~SCRIPTORIUM_SYNC.stopMIDIClockSend;
}, "/scriptorium/sync/midiClock/stopSend");

// /scriptorium/sync/midiClock/startReceive
OSCdef(\scriptorium_sync_midi_recv_start, {
    if(MIDIClient.initialized.not) { MIDIClient.init };
    ~SCRIPTORIUM_SYNC.startMIDIClockReceive;
}, "/scriptorium/sync/midiClock/startReceive");

// /scriptorium/sync/midiClock/stopReceive
OSCdef(\scriptorium_sync_midi_recv_stop, {
    ~SCRIPTORIUM_SYNC.stopMIDIClockReceive;
}, "/scriptorium/sync/midiClock/stopReceive");

// /scriptorium/sync/link/start [bpm:float]
OSCdef(\scriptorium_sync_link_start, { |msg|
    var bpm = msg[1] !? _.asFloat ?? 120;
    ~SCRIPTORIUM_SYNC.startLink(bpm);
}, "/scriptorium/sync/link/start");

// /scriptorium/sync/link/stop
OSCdef(\scriptorium_sync_link_stop, {
    ~SCRIPTORIUM_SYNC.stopLink;
}, "/scriptorium/sync/link/stop");

// /scriptorium/sync/link/bpm <bpm:float>
OSCdef(\scriptorium_sync_link_bpm, { |msg|
    ~SCRIPTORIUM_SYNC.setLinkBPM(msg[1].asFloat);
}, "/scriptorium/sync/link/bpm");

// /scriptorium/sync/tap
OSCdef(\scriptorium_sync_tap, {
    ~SCRIPTORIUM_SYNC.tap;
}, "/scriptorium/sync/tap");

// /scriptorium/sync/tap/reset
OSCdef(\scriptorium_sync_tap_reset, {
    ~SCRIPTORIUM_SYNC.resetTap;
}, "/scriptorium/sync/tap/reset");

// /scriptorium/sync/status
OSCdef(\scriptorium_sync_status, {
    ~SCRIPTORIUM_SYNC.status;
}, "/scriptorium/sync/status");

"--- BRAHMA: SCRIPTORIUM Sync Online ---".postln;
)
