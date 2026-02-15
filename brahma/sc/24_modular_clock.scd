/*
  Phase 5: HOROLOGIUM — Clock Modules
  Master Clock, Divider, Multiplier, Swing, Tap Tempo,
  Burst Generator, Clock Delay, Ableton Link
*/

(
// ==========================================
// MASTER CLOCK (BPM-driven pulse generator)
// ==========================================
SynthDef(\horologium_master, {
    |outBus=0, bpm=120, run=1, swing=0, swingAmount=0.5|

    var freq, pulse;
    freq = (bpm.clip(20, 300) / 60);
    pulse = Impulse.kr(freq) * run.clip(0, 1);
    Out.kr(outBus, pulse);
}).add;

// ==========================================
// CLOCK DIVIDER (input clock → slower outputs)
// ==========================================
SynthDef(\horologium_divider, {
    |inBus=0,
     outBus2=0, outBus3=1, outBus4=2, outBus5=3,
     outBus6=4, outBus7=5, outBus8=6, outBus16=7, outBus32=8|

    var trig, cnt;
    trig = In.kr(inBus, 1);
    cnt = PulseCount.kr(trig);

    Out.kr(outBus2,  Trig1.kr((cnt % 2) < 0.5 * trig, 0.001));
    Out.kr(outBus3,  Trig1.kr((cnt % 3) < 0.5 * trig, 0.001));
    Out.kr(outBus4,  Trig1.kr((cnt % 4) < 0.5 * trig, 0.001));
    Out.kr(outBus5,  Trig1.kr((cnt % 5) < 0.5 * trig, 0.001));
    Out.kr(outBus6,  Trig1.kr((cnt % 6) < 0.5 * trig, 0.001));
    Out.kr(outBus7,  Trig1.kr((cnt % 7) < 0.5 * trig, 0.001));
    Out.kr(outBus8,  Trig1.kr((cnt % 8) < 0.5 * trig, 0.001));
    Out.kr(outBus16, Trig1.kr((cnt % 16) < 0.5 * trig, 0.001));
    Out.kr(outBus32, Trig1.kr((cnt % 32) < 0.5 * trig, 0.001));
}).add;

// ==========================================
// CLOCK MULTIPLIER (input clock → faster outputs)
// ==========================================
SynthDef(\horologium_multiplier, {
    |inBus=0, outBus=0, multiply=2|

    var trig, rate, period, mul;
    trig = In.kr(inBus, 1);

    // Measure incoming clock period via Timer
    period = Timer.kr(trig).max(0.01);
    rate = multiply.clip(1, 8) / period;

    mul = Impulse.kr(rate);
    Out.kr(outBus, mul);
}).add;

// ==========================================
// SWING PROCESSOR (applies swing to incoming clock)
// ==========================================
SynthDef(\horologium_swing, {
    |inBus=0, outBus=0, amount=0.5|
    // amount: 0.5 = straight, 0.66 = triplet swing, 0-1 range

    var trig, cnt, period, isEven, delay, swung;
    trig = In.kr(inBus, 1);
    cnt = PulseCount.kr(trig);
    period = Timer.kr(trig).max(0.001);
    isEven = (cnt % 2) < 0.5;

    // Delay even beats by swing amount
    delay = isEven * period * (amount.clip(0.5, 0.75) - 0.5) * 2;
    swung = DelayN.kr(trig, 0.5, delay);

    Out.kr(outBus, swung);
}).add;

// ==========================================
// BURST GENERATOR (N pulses at rate on single trigger)
// ==========================================
SynthDef(\horologium_burst, {
    |inBus=0, outBus=0, count=4, rate=10, acceleration=0|
    // count: number of pulses (1-32)
    // rate: pulses per second
    // acceleration: rate increase per pulse (-5 to 5)

    var trig, burstActive, pulseCount, burstRate, pulse;
    trig = In.kr(inBus, 1);

    // Count pulses within burst
    pulseCount = PulseCount.kr(Impulse.kr(rate.clip(1, 100)), trig);
    burstActive = pulseCount < count.clip(1, 32);

    // Accelerating rate
    burstRate = (rate + (pulseCount * acceleration.clip(-5, 5))).clip(1, 200);
    pulse = Impulse.kr(burstRate) * burstActive;

    Out.kr(outBus, pulse);
}).add;

// ==========================================
// CLOCK DELAY (shift clock by ms or % of beat)
// ==========================================
SynthDef(\horologium_delay, {
    |inBus=0, outBus=0, delayMs=0, delayPercent=0|
    // delayMs: fixed delay in ms (0-500)
    // delayPercent: delay as % of beat period (0-1)

    var trig, period, totalDelay, delayed;
    trig = In.kr(inBus, 1);
    period = Timer.kr(trig).max(0.01);

    totalDelay = (delayMs.clip(0, 500) / 1000) + (period * delayPercent.clip(0, 0.99));
    delayed = DelayN.kr(trig, 1.0, totalDelay.clip(0, 1.0));

    Out.kr(outBus, delayed);
}).add;

// ==========================================
// TAP TEMPO (language-side, averages last N taps)
// ==========================================
~HOROLOGIUM_TAP = (
    taps: List.new,
    maxTaps: 4,

    tap: { |self|
        self[\taps].add(Main.elapsedTime);
        if(self[\taps].size > self[\maxTaps] + 1) {
            self[\taps].removeAt(0);
        };
        if(self[\taps].size >= 2) {
            var intervals = (self[\taps].size - 1).collect({ |i|
                self[\taps][i+1] - self[\taps][i];
            });
            var avgInterval = intervals.mean;
            var bpm = (60 / avgInterval).clip(20, 300);
            bpm;
        } {
            nil;
        };
    },

    reset: { |self|
        self[\taps] = List.new;
    }
);

// ==========================================
// ABLETON LINK INTEGRATION
// ==========================================
~HOROLOGIUM_LINK = (
    active: false,

    start: { |self, bpm=120|
        // Requires LinkClock quark
        if(\LinkClock.asClass.notNil) {
            self[\clock] = LinkClock(bpm / 60);
            self[\active] = true;
            "HOROLOGIUM: Link started at % BPM".format(bpm).postln;
        } {
            "HOROLOGIUM: LinkClock quark not installed".postln;
        };
    },

    stop: { |self|
        if(self[\active]) {
            self[\clock].stop;
            self[\active] = false;
        };
    },

    getBPM: { |self|
        if(self[\active]) {
            self[\clock].tempo * 60;
        } { nil };
    }
);

// OSC responders
OSCdef(\horologium_tap, { |msg|
    var bpm = ~HOROLOGIUM_TAP.tap;
    if(bpm.notNil) {
        "HOROLOGIUM: Tap tempo = % BPM".format(bpm.round(0.1)).postln;
        // Optionally sync to Chronos
        if(~CHRONOS.notNil) {
            ~CHRONOS[\bpm] = bpm;
        };
    };
}, "/horologium/tap");

OSCdef(\horologium_link_start, { |msg|
    var bpm = msg[1] ? 120;
    ~HOROLOGIUM_LINK.start(bpm);
}, "/horologium/link/start");

OSCdef(\horologium_link_stop, {
    ~HOROLOGIUM_LINK.stop;
}, "/horologium/link/stop");

"--- BRAHMA: HOROLOGIUM Clock Modules Online (7 modules) ---".postln;

// ==========================================
// PATCH BAY REGISTRATION — Clock Modules
// ==========================================
[
    [\horologium_master, [
        [\bpm, "BPM"], [\run, "Run toggle"]
    ]],
    [\horologium_multiplier, [
        [\multiply, "Multiply factor"]
    ]],
    [\horologium_swing, [
        [\amount, "Swing amount"]
    ]],
    [\horologium_burst, [
        [\count, "Burst count"], [\rate, "Burst rate"],
        [\acceleration, "Rate acceleration"]
    ]],
    [\horologium_delay, [
        [\delayMs, "Delay ms"], [\delayPercent, "Delay percent"]
    ]]
].do({ |moduleSpec|
    var synthName = moduleSpec[0];
    var params = moduleSpec[1];
    params.do({ |p|
        ~PATCH_BAY.registerDestination(
            (synthName.asString ++ "_" ++ p[0].asString).asSymbol,
            p[0], synthName.asString ++ " " ++ p[1]
        );
    });
});

// --- MODULE REGISTRY REGISTRATION ---
if(~MODULE_REGISTRY.notNil) {
    // 1. Master Clock — BPM-driven pulse generator
    ~MODULE_REGISTRY.register(\horologium_master, \modular, \horologium_master, [
        (\name: \bpm, \default: 120, \min: 20, \max: 300, \units: "BPM", \desc: "Tempo"),
        (\name: \run, \default: 1, \min: 0, \max: 1, \units: "", \desc: "Run/stop"),
        (\name: \swing, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Swing enable"),
        (\name: \swingAmount, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Swing amount")
    ], ~SC_GRP[\te], "BPM-driven master clock with swing");

    // 2. Clock Divider — input clock to slower outputs
    ~MODULE_REGISTRY.register(\horologium_divider, \modular, \horologium_divider, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Clock input bus")
    ], ~SC_GRP[\te], "Clock divider with /2 /3 /4 /5 /6 /7 /8 /16 /32 outputs");

    // 3. Clock Multiplier — input clock to faster outputs
    ~MODULE_REGISTRY.register(\horologium_multiplier, \modular, \horologium_multiplier, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Clock input bus"),
        (\name: \multiply, \default: 2, \min: 1, \max: 8, \units: "x", \desc: "Multiplication factor")
    ], ~SC_GRP[\te], "Clock multiplier: x1 to x8 rate multiplication");

    // 4. Swing Processor — applies swing to incoming clock
    ~MODULE_REGISTRY.register(\horologium_swing, \modular, \horologium_swing, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Clock input bus"),
        (\name: \amount, \default: 0.5, \min: 0.5, \max: 0.75, \units: "", \desc: "Swing amount (0.5=straight, 0.66=triplet)")
    ], ~SC_GRP[\te], "Swing processor: delays even beats by swing amount");

    // 5. Burst Generator — N pulses at rate on single trigger
    ~MODULE_REGISTRY.register(\horologium_burst, \modular, \horologium_burst, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Trigger input bus"),
        (\name: \count, \default: 4, \min: 1, \max: 32, \units: "", \desc: "Number of burst pulses"),
        (\name: \rate, \default: 10, \min: 1, \max: 100, \units: "Hz", \desc: "Burst pulse rate"),
        (\name: \acceleration, \default: 0, \min: -5, \max: 5, \units: "", \desc: "Rate acceleration per pulse")
    ], ~SC_GRP[\te], "Burst generator: N pulses at configurable rate with acceleration");

    // 6. Clock Delay — shift clock by ms or % of beat
    ~MODULE_REGISTRY.register(\horologium_delay, \modular, \horologium_delay, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Clock input bus"),
        (\name: \delayMs, \default: 0, \min: 0, \max: 500, \units: "ms", \desc: "Fixed delay in milliseconds"),
        (\name: \delayPercent, \default: 0, \min: 0, \max: 0.99, \units: "", \desc: "Delay as percentage of beat period")
    ], ~SC_GRP[\te], "Clock delay: shift by fixed ms or beat-relative percentage");

    // 7. Tap Tempo — language-side tap tempo averaging
    ~MODULE_REGISTRY.register(\HOROLOGIUM_TAP, \modular, \HOROLOGIUM_TAP, [
        (\name: \maxTaps, \default: 4, \min: 2, \max: 16, \units: "", \desc: "Number of taps to average")
    ], ~SC_GRP[\te], "Tap tempo with configurable averaging window");

    // 8. Ableton Link — Link clock integration
    ~MODULE_REGISTRY.register(\HOROLOGIUM_LINK, \modular, \HOROLOGIUM_LINK, [
        (\name: \bpm, \default: 120, \min: 20, \max: 300, \units: "BPM", \desc: "Link tempo")
    ], ~SC_GRP[\te], "Ableton Link integration for network tempo sync");

    "  MODULE_REGISTRY: 8 Horologium clock modules registered".postln;
};
)
