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
)
