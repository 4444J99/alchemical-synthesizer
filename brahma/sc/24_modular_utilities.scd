/*
  Phase 5: GRIMOIRE — Modular Utilities
  Multiple, Attenuverter, Precision Adder, Sequential Switch,
  Analog Switch, Logic, Comparator, Rectifier, Min/Max, Quantizer
*/

(
// ==========================================
// MULTIPLE (1→4 signal splitter)
// ==========================================
SynthDef(\grimoire_multiple, {
    |inBus=0, outBus1=0, outBus2=1, outBus3=2, outBus4=3|

    var sig = In.kr(inBus, 1);
    Out.kr(outBus1, sig);
    Out.kr(outBus2, sig);
    Out.kr(outBus3, sig);
    Out.kr(outBus4, sig);
}).add;

// Audio-rate multiple
SynthDef(\grimoire_multiple_ar, {
    |inBus=0, outBus1=0, outBus2=1, outBus3=2, outBus4=3|

    var sig = In.ar(inBus, 1);
    Out.ar(outBus1, sig);
    Out.ar(outBus2, sig);
    Out.ar(outBus3, sig);
    Out.ar(outBus4, sig);
}).add;

// ==========================================
// ATTENUVERTER (bipolar scaling with offset)
// ==========================================
SynthDef(\grimoire_attenuverter, {
    |inBus=0, outBus=0, amount=1.0, offset=0.0|

    var sig = In.kr(inBus, 1);
    Out.kr(outBus, (sig * amount.clip(-2, 2)) + offset.clip(-5, 5));
}).add;

SynthDef(\grimoire_attenuverter_ar, {
    |inBus=0, outBus=0, amount=1.0, offset=0.0|

    var sig = In.ar(inBus, 1);
    Out.ar(outBus, (sig * amount.clip(-2, 2)) + offset.clip(-5, 5));
}).add;

// ==========================================
// PRECISION ADDER (CV summing with 1V/oct tracking)
// ==========================================
SynthDef(\grimoire_adder, {
    |inBus1=0, inBus2=0, inBus3=0, inBus4=0,
     outBus=0,
     gain1=1, gain2=1, gain3=1, gain4=1|

    var sum;
    sum = (In.kr(inBus1, 1) * gain1)
        + (In.kr(inBus2, 1) * gain2)
        + (In.kr(inBus3, 1) * gain3)
        + (In.kr(inBus4, 1) * gain4);

    Out.kr(outBus, sum);
}).add;

// ==========================================
// SEQUENTIAL SWITCH (rotate between N outputs on trigger)
// ==========================================
SynthDef(\grimoire_seq_switch, {
    |inBus=0, trigBus=0,
     outBus1=0, outBus2=1, outBus3=2, outBus4=3,
     numOutputs=4, mode=0|  // 0=forward, 1=random

    var input, trig, counter, sig;

    input = In.kr(inBus, 1);
    trig = In.kr(trigBus, 1);

    counter = Select.kr(mode.clip(0, 1), [
        Stepper.kr(trig, 0, 0, numOutputs.clip(1, 4) - 1),
        TIRand.kr(0, numOutputs.clip(1, 4) - 1, trig)
    ]);

    // Route input to selected output
    Out.kr(outBus1, input * (counter < 0.5));
    Out.kr(outBus2, input * ((counter > 0.5) * (counter < 1.5)));
    Out.kr(outBus3, input * ((counter > 1.5) * (counter < 2.5)));
    Out.kr(outBus4, input * (counter > 2.5));
}).add;

// ==========================================
// ANALOG SWITCH (CV-controlled A/B routing)
// ==========================================
SynthDef(\grimoire_switch, {
    |inBusA=0, inBusB=1, outBus=0, cvBus=0, threshold=0.5|

    var a, b, cv, sel;
    a = In.ar(inBusA, 1);
    b = In.ar(inBusB, 1);
    cv = In.kr(cvBus, 1);

    sel = (cv > threshold.clip(0, 1)).lag(0.001);

    Out.ar(outBus, XFade2.ar(a, b, sel * 2 - 1));
}).add;

// ==========================================
// LOGIC GATES (for gates/triggers)
// ==========================================
SynthDef(\grimoire_and, {
    |inBus1=0, inBus2=0, outBus=0|
    var a = In.kr(inBus1, 1) > 0.5;
    var b = In.kr(inBus2, 1) > 0.5;
    Out.kr(outBus, (a * b));
}).add;

SynthDef(\grimoire_or, {
    |inBus1=0, inBus2=0, outBus=0|
    var a = In.kr(inBus1, 1) > 0.5;
    var b = In.kr(inBus2, 1) > 0.5;
    Out.kr(outBus, (a + b).clip(0, 1));
}).add;

SynthDef(\grimoire_xor, {
    |inBus1=0, inBus2=0, outBus=0|
    var a = In.kr(inBus1, 1) > 0.5;
    var b = In.kr(inBus2, 1) > 0.5;
    Out.kr(outBus, ((a + b) - (a * b * 2)).abs);
}).add;

SynthDef(\grimoire_not, {
    |inBus=0, outBus=0|
    Out.kr(outBus, 1 - (In.kr(inBus, 1) > 0.5));
}).add;

SynthDef(\grimoire_nand, {
    |inBus1=0, inBus2=0, outBus=0|
    var a = In.kr(inBus1, 1) > 0.5;
    var b = In.kr(inBus2, 1) > 0.5;
    Out.kr(outBus, 1 - (a * b));
}).add;

SynthDef(\grimoire_nor, {
    |inBus1=0, inBus2=0, outBus=0|
    var a = In.kr(inBus1, 1) > 0.5;
    var b = In.kr(inBus2, 1) > 0.5;
    Out.kr(outBus, 1 - (a + b).clip(0, 1));
}).add;

// ==========================================
// COMPARATOR (A>B → gate, with hysteresis)
// ==========================================
SynthDef(\grimoire_comparator, {
    |inBusA=0, inBusB=0, outBus=0, hysteresis=0.01|

    var a, b, gate;
    a = In.kr(inBusA, 1);
    b = In.kr(inBusB, 1);

    gate = Schmidt.kr(a - b, hysteresis.clip(0, 0.5).neg, hysteresis.clip(0, 0.5));
    Out.kr(outBus, gate);
}).add;

// ==========================================
// RECTIFIER (half/full wave rectification of CV)
// ==========================================
SynthDef(\grimoire_rectifier, {
    |inBus=0, outBus=0, mode=0|  // 0=full, 1=half (positive only)

    var sig = In.kr(inBus, 1);

    sig = Select.kr(mode.clip(0, 1), [
        sig.abs,            // Full wave
        sig.max(0)          // Half wave (positive only)
    ]);

    Out.kr(outBus, sig);
}).add;

// ==========================================
// MIN / MAX
// ==========================================
SynthDef(\grimoire_min, {
    |inBus1=0, inBus2=0, outBus=0|
    Out.kr(outBus, min(In.kr(inBus1, 1), In.kr(inBus2, 1)));
}).add;

SynthDef(\grimoire_max, {
    |inBus1=0, inBus2=0, outBus=0|
    Out.kr(outBus, max(In.kr(inBus1, 1), In.kr(inBus2, 1)));
}).add;

// ==========================================
// QUANTIZER (snap CV to scale degrees — uses BrahmaScale)
// ==========================================
// Language-side quantizer (runs in a routine reading/writing buses)
~GRIMOIRE_QUANTIZER = (
    active: false,

    start: { |self, inBus, outBus, rate=100|
        self[\active] = true;
        self[\routine] = Routine({
            loop {
                if(self[\active]) {
                    var rawCV = inBus.getSynchronous;
                    var freq = rawCV.linexp(0, 1, 20, 20000);
                    var quantized = ~BRAHMA_TUNING[\currentScale].quantize(freq, ~BRAHMA_TUNING[\rootHz]);
                    var quantizedCV = quantized.explin(20, 20000, 0, 1);
                    outBus.set(quantizedCV);
                };
                (1 / rate).wait;
            };
        }).play;
        "GRIMOIRE: Quantizer started".postln;
    },

    stop: { |self|
        self[\active] = false;
        if(self[\routine].notNil) {
            self[\routine].stop;
            self[\routine] = nil;
        };
    }
);

// OSC responders for utilities
OSCdef(\grimoire_quant_start, { |msg|
    var inBusIdx = msg[1].asInteger;
    var outBusIdx = msg[2].asInteger;
    var inBus = Bus(\control, inBusIdx, 1, s);
    var outBus = Bus(\control, outBusIdx, 1, s);
    ~GRIMOIRE_QUANTIZER.start(inBus, outBus);
}, "/grimoire/quantizer/start");

OSCdef(\grimoire_quant_stop, {
    ~GRIMOIRE_QUANTIZER.stop;
}, "/grimoire/quantizer/stop");

"--- BRAHMA: GRIMOIRE Utilities Online (18 modules) ---".postln;
)
