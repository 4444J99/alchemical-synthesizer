/*
  Phase 7: CORPUS HERMETICUM — Interaction Controllers
  SIGILLUM (Touch Plates), MERIDIAN (Ribbon Controller),
  TETRAGRAMMATON (XY Pad), TACTUS (Contact Mic/Gesture)
*/

(
// ==========================================
// 1. SIGILLUM — Touch Plate CV Generator
// ==========================================
// One instance per touch pad. Outputs gate, pressure,
// and XY position to separate control buses with lag smoothing.
SynthDef(\sigillum_pad, {
    |outBusGate=0, outBusPressure=1, outBusX=2, outBusY=3,
     gate=0, pressure=0, posX=0.5, posY=0.5|

    var gateSmooth, pressSmooth, xSmooth, ySmooth;

    // Smooth all outputs to prevent CV stepping artifacts
    gateSmooth    = gate.lag(0.005);
    pressSmooth   = pressure.clip(0, 1).lag(0.01);
    xSmooth       = posX.clip(0, 1).lag(0.01);
    ySmooth       = posY.clip(0, 1).lag(0.01);

    Out.kr(outBusGate,     gateSmooth);
    Out.kr(outBusPressure, pressSmooth);
    Out.kr(outBusX,        xSmooth);
    Out.kr(outBusY,        ySmooth);
}).add;

// ==========================================
// 2. MERIDIAN — Ribbon Controller
// ==========================================
// Continuous ribbon with position, velocity, and gate outputs.
// mode: 0=unipolar (0-1), 1=bipolar (-1 to 1)
SynthDef(\meridian_ribbon, {
    |outBusPos=0, outBusVel=1, outBusGate=2,
     position=0.5, velocity=0, gate=0, mode=0|

    var posSmooth, posRaw, velDerived, posOut, gateSmooth;

    // Fast tracking for ribbon — 5ms lag
    posRaw    = position.clip(0, 1);
    posSmooth = posRaw.lag(0.005);

    // Derive velocity from rate of position change
    // Slope.kr returns the difference per control period
    velDerived = Slope.kr(posSmooth).abs.clip(0, 1).lag(0.02);

    // Mode: unipolar (0-1) or bipolar (-1 to 1)
    posOut = Select.kr(mode.clip(0, 1), [
        posSmooth,                    // 0: unipolar
        posSmooth.linlin(0, 1, -1, 1) // 1: bipolar
    ]);

    gateSmooth = gate.lag(0.005);

    Out.kr(outBusPos,  posOut);
    Out.kr(outBusVel,  velDerived);
    Out.kr(outBusGate, gateSmooth);
}).add;

// ==========================================
// 3. TETRAGRAMMATON — 4-Corner Audio Morph (XY Pad)
// ==========================================
// Bilinear interpolation between 4 audio sources.
// Corner mapping: 1=NW(0,0), 2=NE(1,0), 3=SW(0,1), 4=SE(1,1)
// Mix: (1-x)*(1-y)*src1 + x*(1-y)*src2 + (1-x)*y*src3 + x*y*src4
SynthDef(\tetragrammaton_morph, {
    |inBus1=0, inBus2=1, inBus3=2, inBus4=3,
     outBus=0, posX=0.5, posY=0.5|

    var src1, src2, src3, src4;
    var x, y, mix;

    src1 = In.ar(inBus1, 1); // NW (0,0)
    src2 = In.ar(inBus2, 1); // NE (1,0)
    src3 = In.ar(inBus3, 1); // SW (0,1)
    src4 = In.ar(inBus4, 1); // SE (1,1)

    x = posX.clip(0, 1).lag(0.005);
    y = posY.clip(0, 1).lag(0.005);

    // Bilinear interpolation
    mix = ((1 - x) * (1 - y) * src1)
        + (x * (1 - y) * src2)
        + ((1 - x) * y * src3)
        + (x * y * src4);

    Out.ar(outBus, mix);
}).add;

// ==========================================
// 4. TETRAGRAMMATON CV — 4-Corner Control Rate Morph
// ==========================================
// Same bilinear interpolation at control rate for CV mixing.
SynthDef(\tetragrammaton_cv, {
    |inBus1=0, inBus2=1, inBus3=2, inBus4=3,
     outBus=0, posX=0.5, posY=0.5|

    var src1, src2, src3, src4;
    var x, y, mix;

    src1 = In.kr(inBus1, 1); // NW (0,0)
    src2 = In.kr(inBus2, 1); // NE (1,0)
    src3 = In.kr(inBus3, 1); // SW (0,1)
    src4 = In.kr(inBus4, 1); // SE (1,1)

    x = posX.clip(0, 1).lag(0.005);
    y = posY.clip(0, 1).lag(0.005);

    // Bilinear interpolation (control rate)
    mix = ((1 - x) * (1 - y) * src1)
        + (x * (1 - y) * src2)
        + ((1 - x) * y * src3)
        + (x * y * src4);

    Out.kr(outBus, mix);
}).add;

// ==========================================
// 5. TACTUS — Gesture/Impact to Gate+CV Converter
// ==========================================
// Audio input -> amplitude detection -> gate when exceeding
// threshold + smoothed CV output as envelope follower.
SynthDef(\tactus_gate, {
    |inBus=0, outBusGate=0, outBusCV=1,
     threshold=0.3, attack=0.001, release=0.1|

    var input, amp, gateOut, cvOut;

    input = In.ar(inBus, 1);

    // Amplitude tracking with configurable attack/release
    amp = Amplitude.kr(input,
        attack.clip(0.0001, 0.1),
        release.clip(0.001, 2.0)
    );

    // Gate: fires when amplitude exceeds threshold (with hysteresis)
    gateOut = Schmidt.kr(amp,
        threshold.clip(0.01, 1.0) * 0.9,  // Lower threshold (off)
        threshold.clip(0.01, 1.0)           // Upper threshold (on)
    );

    // CV output: smoothed amplitude as envelope follower
    cvOut = amp.clip(0, 1);

    Out.kr(outBusGate, gateOut);
    Out.kr(outBusCV,   cvOut);
}).add;

// ==========================================
// TETRAGRAMMATON GESTURE RECORDER
// ==========================================
// Language-side XY path recorder/player for gesture playback.
// Records position samples at configurable rate, plays them
// back into control buses with optional looping.
~TETRAGRAMMATON_RECORDER = (
    recording: false,
    playing: false,
    gesturePath: List.new,
    pos: 0,
    rate: 30, // Samples per second
    currentX: 0.5,
    currentY: 0.5,

    startRecord: { |self|
        self[\gesturePath] = List.new;
        self[\recording] = true;
        self[\routine] = Routine({
            loop {
                if(self[\recording]) {
                    // Record current XY (set externally via OSC or direct assignment)
                    self[\gesturePath].add([self[\currentX] ? 0.5, self[\currentY] ? 0.5]);
                };
                (1 / self[\rate]).wait;
            };
        }).play;
        "CORPUS HERMETICUM: Gesture recording started".postln;
    },

    stopRecord: { |self|
        self[\recording] = false;
        if(self[\routine].notNil) { self[\routine].stop };
        ("CORPUS HERMETICUM: Gesture recorded — " ++ self[\gesturePath].size ++ " points").postln;
    },

    startPlay: { |self, loop=true, outBusX, outBusY|
        self[\playing] = true;
        self[\pos] = 0;
        self[\playRoutine] = Routine({
            loop {
                if(self[\playing] and: { self[\gesturePath].size > 0 }) {
                    var point = self[\gesturePath][self[\pos]];
                    if(outBusX.notNil) { outBusX.set(point[0]) };
                    if(outBusY.notNil) { outBusY.set(point[1]) };
                    self[\pos] = self[\pos] + 1;
                    if(self[\pos] >= self[\gesturePath].size) {
                        if(loop) { self[\pos] = 0 } { self[\playing] = false };
                    };
                };
                (1 / self[\rate]).wait;
            };
        }).play;
        "CORPUS HERMETICUM: Gesture playback started".postln;
    },

    stopPlay: { |self|
        self[\playing] = false;
        if(self[\playRoutine].notNil) { self[\playRoutine].stop };
        "CORPUS HERMETICUM: Gesture playback stopped".postln;
    }
);

// ==========================================
// OSC RESPONDERS — Interaction Controllers
// ==========================================

// --- SIGILLUM: Touch Plate Input ---
// /sigillum/pad [padIndex] [gate] [pressure] [posX] [posY]
// Routes OSC touch data to the corresponding Synth instance by index.
OSCdef(\sigillum_pad_osc, { |msg|
    var padIndex  = msg[1].asInteger;
    var gate      = msg[2].asFloat;
    var pressure  = msg[3].asFloat;
    var posX      = msg[4].asFloat;
    var posY      = msg[5].asFloat;

    // Look up synth in global registry by pad index
    if(~SIGILLUM_PADS.notNil and: { ~SIGILLUM_PADS[padIndex].notNil }) {
        ~SIGILLUM_PADS[padIndex].set(
            \gate, gate,
            \pressure, pressure,
            \posX, posX,
            \posY, posY
        );
    } {
        ("SIGILLUM: No pad registered at index " ++ padIndex).postln;
    };
}, "/sigillum/pad");

// --- MERIDIAN: Ribbon Controller ---
// /meridian/position [value]
OSCdef(\meridian_position_osc, { |msg|
    var value = msg[1].asFloat;
    if(~MERIDIAN_SYNTH.notNil) {
        ~MERIDIAN_SYNTH.set(\position, value);
    };
}, "/meridian/position");

// /meridian/gate [value]
OSCdef(\meridian_gate_osc, { |msg|
    var value = msg[1].asFloat;
    if(~MERIDIAN_SYNTH.notNil) {
        ~MERIDIAN_SYNTH.set(\gate, value);
    };
}, "/meridian/gate");

// --- TETRAGRAMMATON: XY Pad ---
// /tetragrammaton/xy [x] [y]
OSCdef(\tetragrammaton_xy_osc, { |msg|
    var x = msg[1].asFloat;
    var y = msg[2].asFloat;

    // Update the morph synth if it exists
    if(~TETRAGRAMMATON_SYNTH.notNil) {
        ~TETRAGRAMMATON_SYNTH.set(\posX, x, \posY, y);
    };

    // Feed the gesture recorder's current position
    ~TETRAGRAMMATON_RECORDER[\currentX] = x;
    ~TETRAGRAMMATON_RECORDER[\currentY] = y;
}, "/tetragrammaton/xy");

// /tetragrammaton/record/start
OSCdef(\tetragrammaton_rec_start, { |msg|
    ~TETRAGRAMMATON_RECORDER.startRecord;
}, "/tetragrammaton/record/start");

// /tetragrammaton/record/stop
OSCdef(\tetragrammaton_rec_stop, { |msg|
    ~TETRAGRAMMATON_RECORDER.stopRecord;
}, "/tetragrammaton/record/stop");

// /tetragrammaton/play/start
OSCdef(\tetragrammaton_play_start, { |msg|
    var loop = if(msg[1].notNil) { msg[1].asInteger > 0 } { true };
    ~TETRAGRAMMATON_RECORDER.startPlay(loop,
        ~TETRAGRAMMATON_BUS_X,
        ~TETRAGRAMMATON_BUS_Y
    );
}, "/tetragrammaton/play/start");

// /tetragrammaton/play/stop
OSCdef(\tetragrammaton_play_stop, { |msg|
    ~TETRAGRAMMATON_RECORDER.stopPlay;
}, "/tetragrammaton/play/stop");

// --- TACTUS: Gesture Threshold ---
// /tactus/threshold [value]
OSCdef(\tactus_threshold_osc, { |msg|
    var value = msg[1].asFloat;
    if(~TACTUS_SYNTH.notNil) {
        ~TACTUS_SYNTH.set(\threshold, value);
    };
}, "/tactus/threshold");

// ==========================================
// GLOBAL STATE INITIALIZATION
// ==========================================
// Pad registry: stores Synth references indexed by pad number.
// Populate these when instantiating SIGILLUM pads in a performance patch.
~SIGILLUM_PADS = IdentityDictionary.new;

// Optional bus references for TETRAGRAMMATON gesture playback.
// Assign Bus objects here when setting up a performance patch.
~TETRAGRAMMATON_BUS_X = nil;
~TETRAGRAMMATON_BUS_Y = nil;

// Placeholder synth references — assigned during performance instantiation
~MERIDIAN_SYNTH = nil;
~TETRAGRAMMATON_SYNTH = nil;
~TACTUS_SYNTH = nil;

"--- BRAHMA: CORPUS HERMETICUM Controllers Online (5 modules) ---".postln;
"  SIGILLUM (Touch Plates) | MERIDIAN (Ribbon) | TETRAGRAMMATON (XY Morph AR+KR)".postln;
"  TACTUS (Gesture Gate) | Gesture Recorder (Language-side)".postln;
)
