/*
  Phase 9: SCRIPTORIUM — Audio Monitoring
  Level Meters, Spectrum Analyzer, Oscilloscope, Tuner, CPU Monitor
*/

(
// ==========================================
// SYNTHDEF: Peak + RMS Level Meter
// ==========================================
SynthDef(\scriptorium_meter, {
    |inBus=0, outBusPeak=0, outBusRMS=1|

    var in, peak, rms;

    in = In.ar(inBus, 1);

    // Peak level (fast attack, medium release)
    peak = Peak.kr(in, Impulse.kr(20)); // Reset 20x/sec for responsive metering

    // RMS via Amplitude.kr (approximation with appropriate attack/release)
    rms = Amplitude.kr(in, attackTime: 0.01, releaseTime: 0.3);

    Out.kr(outBusPeak, peak);
    Out.kr(outBusRMS, rms);
}).add;

// Stereo variant — writes peak/rms for L and R channels
SynthDef(\scriptorium_meter_stereo, {
    |inBus=0, outBusPeakL=0, outBusPeakR=1, outBusRMSL=2, outBusRMSR=3|

    var in, peakL, peakR, rmsL, rmsR;

    in = In.ar(inBus, 2);

    peakL = Peak.kr(in[0], Impulse.kr(20));
    peakR = Peak.kr(in[1], Impulse.kr(20));

    rmsL = Amplitude.kr(in[0], attackTime: 0.01, releaseTime: 0.3);
    rmsR = Amplitude.kr(in[1], attackTime: 0.01, releaseTime: 0.3);

    Out.kr(outBusPeakL, peakL);
    Out.kr(outBusPeakR, peakR);
    Out.kr(outBusRMSL, rmsL);
    Out.kr(outBusRMSR, rmsR);
}).add;

// ==========================================
// SYNTHDEF: Oscilloscope Buffer Writer
// ==========================================
SynthDef(\scriptorium_scope, {
    |inBus=0, scopeBufnum=0|

    var in;

    in = In.ar(inBus, 1);

    // Write waveform to a small looping buffer for scope display
    RecordBuf.ar(in, scopeBufnum, loop: 1, doneAction: 0);
}).add;

// ==========================================
// SYNTHDEF: Pitch Detector (Tuner)
// ==========================================
SynthDef(\scriptorium_tuner, {
    |inBus=0, outBusPitch=0, outBusHasFreq=1|

    var in, freq, hasFreq;

    in = In.ar(inBus, 1);

    // Pitch.kr returns [freq, hasFreq]
    // hasFreq > 0 means confident pitch detection
    # freq, hasFreq = Pitch.kr(
        in,
        initFreq: 440,
        minFreq: 30,
        maxFreq: 4200,
        execFreq: 100, // Analysis rate
        clar: 1 // Use clarity measure
    );

    Out.kr(outBusPitch, freq);
    Out.kr(outBusHasFreq, hasFreq);
}).add;

// ==========================================
// SYNTHDEF: Spectral Analyzer (sends FFT bins to control bus)
// ==========================================
SynthDef(\scriptorium_spectrum, {
    |inBus=0, fftBufnum=0, outBus=0, numBands=16|

    var in, chain, magnitudes;

    in = In.ar(inBus, 1);
    chain = FFT(fftBufnum, in);

    // Extract magnitudes from FFT chain
    // Write spectral centroid and flatness as summary metrics
    Out.kr(outBus, [
        SpecCentroid.kr(chain),
        SpecFlatness.kr(chain)
    ]);
}).add;

// ==========================================
// MONITORING MANAGER
// ==========================================
~SCRIPTORIUM_MONITOR = (
    meters: IdentityDictionary.new,
    scopes: IdentityDictionary.new,
    tuners: IdentityDictionary.new,
    broadcastRate: 30, // Hz
    broadcastAddr: nil,
    running: false,
    routine: nil,

    // ==========================================
    // INITIALIZATION
    // ==========================================
    init: { |self|
        self[\broadcastAddr] = NetAddr("127.0.0.1", 57122);
        "SCRIPTORIUM MONITOR: Initialized (broadcast → 127.0.0.1:57122)".postln;
    },

    // ==========================================
    // LEVEL METERS
    // ==========================================

    addMeter: { |self, name, inBus|
        var peakBus = Bus.control(s, 1);
        var rmsBus = Bus.control(s, 1);
        var synth = Synth(\scriptorium_meter, [
            \inBus, inBus,
            \outBusPeak, peakBus.index,
            \outBusRMS, rmsBus.index
        ]);
        self[\meters][name.asSymbol] = (
            synth: synth,
            peakBus: peakBus,
            rmsBus: rmsBus,
            inBus: inBus
        );
        "SCRIPTORIUM MONITOR: Meter '%' added on bus %".format(name, inBus).postln;
    },

    addStereoMeter: { |self, name, inBus|
        var peakBusL = Bus.control(s, 1);
        var peakBusR = Bus.control(s, 1);
        var rmsBusL = Bus.control(s, 1);
        var rmsBusR = Bus.control(s, 1);
        var synth = Synth(\scriptorium_meter_stereo, [
            \inBus, inBus,
            \outBusPeakL, peakBusL.index,
            \outBusPeakR, peakBusR.index,
            \outBusRMSL, rmsBusL.index,
            \outBusRMSR, rmsBusR.index
        ]);
        self[\meters][name.asSymbol] = (
            synth: synth,
            peakBusL: peakBusL,
            peakBusR: peakBusR,
            rmsBusL: rmsBusL,
            rmsBusR: rmsBusR,
            stereo: true,
            inBus: inBus
        );
        "SCRIPTORIUM MONITOR: Stereo meter '%' added on bus %".format(name, inBus).postln;
    },

    freeMeter: { |self, name|
        var meter = self[\meters][name.asSymbol];
        if(meter.notNil) {
            meter[\synth].free;
            if(meter[\stereo] == true) {
                meter[\peakBusL].free;
                meter[\peakBusR].free;
                meter[\rmsBusL].free;
                meter[\rmsBusR].free;
            } {
                meter[\peakBus].free;
                meter[\rmsBus].free;
            };
            self[\meters].removeAt(name.asSymbol);
            "SCRIPTORIUM MONITOR: Meter '%' removed".format(name).postln;
        };
    },

    // ==========================================
    // OSCILLOSCOPE
    // ==========================================

    addScope: { |self, name, inBus, scopeFrames=1024|
        var scopeBuf = Buffer.alloc(s, scopeFrames, 1);
        var synth = Synth(\scriptorium_scope, [
            \inBus, inBus,
            \scopeBufnum, scopeBuf.bufnum
        ]);
        self[\scopes][name.asSymbol] = (
            synth: synth,
            buffer: scopeBuf,
            inBus: inBus
        );
        "SCRIPTORIUM MONITOR: Scope '%' added on bus %".format(name, inBus).postln;
    },

    freeScope: { |self, name|
        var scope = self[\scopes][name.asSymbol];
        if(scope.notNil) {
            scope[\synth].free;
            scope[\buffer].free;
            self[\scopes].removeAt(name.asSymbol);
        };
    },

    // ==========================================
    // TUNER
    // ==========================================

    addTuner: { |self, name, inBus|
        var pitchBus = Bus.control(s, 1);
        var hasFreqBus = Bus.control(s, 1);
        var synth = Synth(\scriptorium_tuner, [
            \inBus, inBus,
            \outBusPitch, pitchBus.index,
            \outBusHasFreq, hasFreqBus.index
        ]);
        self[\tuners][name.asSymbol] = (
            synth: synth,
            pitchBus: pitchBus,
            hasFreqBus: hasFreqBus,
            inBus: inBus
        );
        "SCRIPTORIUM MONITOR: Tuner '%' added on bus %".format(name, inBus).postln;
    },

    freeTuner: { |self, name|
        var tuner = self[\tuners][name.asSymbol];
        if(tuner.notNil) {
            tuner[\synth].free;
            tuner[\pitchBus].free;
            tuner[\hasFreqBus].free;
            self[\tuners].removeAt(name.asSymbol);
        };
    },

    // ==========================================
    // BROADCAST (OSC → Visual Cortex / Web UI)
    // ==========================================

    startBroadcast: { |self|
        self[\running] = true;
        self[\routine] = Routine({
            loop {
                if(self[\running]) {
                    // Meter levels
                    self[\meters].keysValuesDo({ |name, meter|
                        if(meter[\stereo] == true) {
                            var peakL = meter[\peakBusL].getSynchronous;
                            var peakR = meter[\peakBusR].getSynchronous;
                            var rmsL = meter[\rmsBusL].getSynchronous;
                            var rmsR = meter[\rmsBusR].getSynchronous;
                            self[\broadcastAddr].sendMsg(
                                "/brahma/meter/stereo", name, peakL, peakR, rmsL, rmsR);
                        } {
                            var peak = meter[\peakBus].getSynchronous;
                            var rms = meter[\rmsBus].getSynchronous;
                            self[\broadcastAddr].sendMsg(
                                "/brahma/meter", name, peak, rms);
                        };
                    });

                    // Tuner data
                    self[\tuners].keysValuesDo({ |name, tuner|
                        var freq = tuner[\pitchBus].getSynchronous;
                        var hasFreq = tuner[\hasFreqBus].getSynchronous;
                        self[\broadcastAddr].sendMsg(
                            "/brahma/tuner", name, freq, hasFreq);
                    });

                    // CPU load
                    self[\broadcastAddr].sendMsg(
                        "/brahma/cpu", s.avgCPU, s.peakCPU);
                };

                (1 / self[\broadcastRate]).wait;
            };
        }).play;
        "SCRIPTORIUM MONITOR: Broadcast started at % Hz".format(self[\broadcastRate]).postln;
    },

    stopBroadcast: { |self|
        self[\running] = false;
        if(self[\routine].notNil) {
            self[\routine].stop;
            self[\routine] = nil;
        };
        "SCRIPTORIUM MONITOR: Broadcast stopped".postln;
    },

    // ==========================================
    // CLEANUP
    // ==========================================

    freeAll: { |self|
        self.stopBroadcast;
        self[\meters].keys.do({ |name| self.freeMeter(name) });
        self[\scopes].keys.do({ |name| self.freeScope(name) });
        self[\tuners].keys.do({ |name| self.freeTuner(name) });
        "SCRIPTORIUM MONITOR: All monitors freed".postln;
    },

    // ==========================================
    // STATUS
    // ==========================================

    status: { |self|
        "SCRIPTORIUM MONITOR STATUS:".postln;
        "  Meters: %".format(self[\meters].keys.asArray).postln;
        "  Scopes: %".format(self[\scopes].keys.asArray).postln;
        "  Tuners: %".format(self[\tuners].keys.asArray).postln;
        "  Broadcasting: % at % Hz".format(self[\running], self[\broadcastRate]).postln;
        "  CPU: avg=%, peak=%".format(s.avgCPU.round(0.1), s.peakCPU.round(0.1)).postln;
    }
);

// Initialize on load
~SCRIPTORIUM_MONITOR.init;

// ==========================================
// OSC RESPONDERS
// ==========================================

// /scriptorium/meter/add <name:string> <inBus:int>
OSCdef(\scriptorium_meter_add, { |msg|
    var name = msg[1].asString;
    var inBus = msg[2].asInteger;
    ~SCRIPTORIUM_MONITOR.addMeter(name, inBus);
}, "/scriptorium/meter/add");

// /scriptorium/meter/addStereo <name:string> <inBus:int>
OSCdef(\scriptorium_meter_add_stereo, { |msg|
    var name = msg[1].asString;
    var inBus = msg[2].asInteger;
    ~SCRIPTORIUM_MONITOR.addStereoMeter(name, inBus);
}, "/scriptorium/meter/addStereo");

// /scriptorium/meter/remove <name:string>
OSCdef(\scriptorium_meter_remove, { |msg|
    ~SCRIPTORIUM_MONITOR.freeMeter(msg[1].asString);
}, "/scriptorium/meter/remove");

// /scriptorium/scope/add <name:string> <inBus:int> [scopeFrames:int]
OSCdef(\scriptorium_scope_add, { |msg|
    var name = msg[1].asString;
    var inBus = msg[2].asInteger;
    var frames = msg[3] !? _.asInteger ?? 1024;
    ~SCRIPTORIUM_MONITOR.addScope(name, inBus, frames);
}, "/scriptorium/scope/add");

// /scriptorium/scope/remove <name:string>
OSCdef(\scriptorium_scope_remove, { |msg|
    ~SCRIPTORIUM_MONITOR.freeScope(msg[1].asString);
}, "/scriptorium/scope/remove");

// /scriptorium/tuner/add <name:string> <inBus:int>
OSCdef(\scriptorium_tuner_add, { |msg|
    var name = msg[1].asString;
    var inBus = msg[2].asInteger;
    ~SCRIPTORIUM_MONITOR.addTuner(name, inBus);
}, "/scriptorium/tuner/add");

// /scriptorium/tuner/remove <name:string>
OSCdef(\scriptorium_tuner_remove, { |msg|
    ~SCRIPTORIUM_MONITOR.freeTuner(msg[1].asString);
}, "/scriptorium/tuner/remove");

// /scriptorium/monitor/start — begin OSC broadcast
OSCdef(\scriptorium_monitor_start, {
    ~SCRIPTORIUM_MONITOR.startBroadcast;
}, "/scriptorium/monitor/start");

// /scriptorium/monitor/stop — halt OSC broadcast
OSCdef(\scriptorium_monitor_stop, {
    ~SCRIPTORIUM_MONITOR.stopBroadcast;
}, "/scriptorium/monitor/stop");

// /scriptorium/monitor/status
OSCdef(\scriptorium_monitor_status, {
    ~SCRIPTORIUM_MONITOR.status;
}, "/scriptorium/monitor/status");

// /scriptorium/monitor/freeAll
OSCdef(\scriptorium_monitor_free_all, {
    ~SCRIPTORIUM_MONITOR.freeAll;
}, "/scriptorium/monitor/freeAll");

"--- BRAHMA: SCRIPTORIUM Monitoring Online ---".postln;
)
