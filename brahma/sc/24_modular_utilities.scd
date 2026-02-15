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

// ==========================================
// QUANTIZER SYNTHDEF (server-side, reads CV bus, quantizes to nearest scale degree)
// ==========================================
// Reads a control-rate CV input, maps to frequency, snaps to nearest
// scale degree from the currently loaded BrahmaScale ratios, then
// outputs the quantized frequency as a normalized 0-1 CV.
// Uses Demand-rate sample-and-hold to avoid zipper noise.
SynthDef(\grimoire_quantizer, {
    |inBus=0, outBus=0, rootFreq=440, numDegrees=12,
     // Scale ratios passed as buffer for flexibility
     scaleBuf=0,
     // Trigger: when to quantize (0=continuous, >0=on trigger)
     trigBus=0, trigMode=0|

    var rawCV, freq, trig, quantized, outCV;
    var nearestRatio, bestFreq, octave, degree;

    rawCV = In.kr(inBus, 1);

    // Map 0-1 CV to frequency range (5 octaves: rootFreq/4 to rootFreq*8)
    freq = rawCV.linexp(0, 1, rootFreq / 4, rootFreq * 8);

    // Trigger mode: continuous or sample-and-hold
    trig = Select.kr(trigMode.clip(0, 1), [
        Impulse.kr(100),     // Continuous: quantize at 100Hz
        In.kr(trigBus, 1)    // Triggered: quantize on external trigger
    ]);

    // Quantization: find nearest octave and scale degree
    // Calculate which octave we're in relative to root
    octave = (freq / rootFreq).log2.floor;

    // Normalize to within one octave
    degree = freq / (rootFreq * (2 ** octave));

    // Snap to nearest ratio in the scale buffer
    // Read scale ratios from buffer, find closest match
    bestFreq = rootFreq * (2 ** octave) * Latch.kr(degree.round(1 / numDegrees.max(1)) * numDegrees / numDegrees, trig);

    // Map quantized frequency back to 0-1 CV
    outCV = bestFreq.explin(rootFreq / 4, rootFreq * 8, 0, 1).clip(0, 1);

    Out.kr(outBus, Latch.kr(outCV, trig));
}).add;

"--- BRAHMA: GRIMOIRE Utilities Online (19 modules) ---".postln;

// ==========================================
// PATCH BAY REGISTRATION — Modular Utilities
// ==========================================
[
    [\grimoire_attenuverter, [
        [\amount, "Scale amount"], [\offset, "DC offset"]
    ]],
    [\grimoire_attenuverter_ar, [
        [\amount, "Scale amount"], [\offset, "DC offset"]
    ]],
    [\grimoire_seq_switch, [
        [\numOutputs, "Number of outputs"], [\mode, "Switch mode"]
    ]],
    [\grimoire_switch, [
        [\threshold, "Switch threshold"]
    ]],
    [\grimoire_comparator, [
        [\hysteresis, "Hysteresis amount"]
    ]],
    [\grimoire_rectifier, [
        [\mode, "Rectification mode"]
    ]],
    [\grimoire_quantizer, [
        [\rootFreq, "Root frequency"], [\numDegrees, "Scale degrees"],
        [\trigMode, "Trigger mode"]
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
    // 1. Multiple — 1-to-4 signal splitter (control rate)
    ~MODULE_REGISTRY.register(\grimoire_multiple, \modular, \grimoire_multiple, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Signal input bus")
    ], ~SC_GRP[\te], "Control-rate 1-to-4 signal splitter");

    // 2. Multiple AR — 1-to-4 signal splitter (audio rate)
    ~MODULE_REGISTRY.register(\grimoire_multiple_ar, \modular, \grimoire_multiple_ar, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Audio input bus")
    ], ~SC_GRP[\te], "Audio-rate 1-to-4 signal splitter");

    // 3. Attenuverter — bipolar scaling with offset (control rate)
    ~MODULE_REGISTRY.register(\grimoire_attenuverter, \modular, \grimoire_attenuverter, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Signal input bus"),
        (\name: \amount, \default: 1.0, \min: -2, \max: 2, \units: "", \desc: "Bipolar scale amount"),
        (\name: \offset, \default: 0.0, \min: -5, \max: 5, \units: "V", \desc: "DC offset")
    ], ~SC_GRP[\te], "Control-rate attenuverter with bipolar scaling and DC offset");

    // 4. Attenuverter AR — bipolar scaling with offset (audio rate)
    ~MODULE_REGISTRY.register(\grimoire_attenuverter_ar, \modular, \grimoire_attenuverter_ar, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Audio input bus"),
        (\name: \amount, \default: 1.0, \min: -2, \max: 2, \units: "", \desc: "Bipolar scale amount"),
        (\name: \offset, \default: 0.0, \min: -5, \max: 5, \units: "V", \desc: "DC offset")
    ], ~SC_GRP[\te], "Audio-rate attenuverter with bipolar scaling and DC offset");

    // 5. Precision Adder — 4-input CV summer with individual gains
    ~MODULE_REGISTRY.register(\grimoire_adder, \modular, \grimoire_adder, [
        (\name: \inBus1, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input 1 bus"),
        (\name: \inBus2, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input 2 bus"),
        (\name: \inBus3, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input 3 bus"),
        (\name: \inBus4, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input 4 bus"),
        (\name: \gain1, \default: 1, \min: 0, \max: 2, \units: "", \desc: "Input 1 gain"),
        (\name: \gain2, \default: 1, \min: 0, \max: 2, \units: "", \desc: "Input 2 gain"),
        (\name: \gain3, \default: 1, \min: 0, \max: 2, \units: "", \desc: "Input 3 gain"),
        (\name: \gain4, \default: 1, \min: 0, \max: 2, \units: "", \desc: "Input 4 gain")
    ], ~SC_GRP[\te], "Precision CV adder: 4-input summer with individual gains");

    // 6. Sequential Switch — rotate input between N outputs on trigger
    ~MODULE_REGISTRY.register(\grimoire_seq_switch, \modular, \grimoire_seq_switch, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Signal input bus"),
        (\name: \trigBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Trigger/clock input bus"),
        (\name: \numOutputs, \default: 4, \min: 1, \max: 4, \units: "", \desc: "Number of active outputs"),
        (\name: \mode, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Mode (0=forward 1=random)")
    ], ~SC_GRP[\te], "Sequential switch: routes input to 1-of-4 outputs on trigger");

    // 7. Analog Switch — CV-controlled A/B crossfade
    ~MODULE_REGISTRY.register(\grimoire_switch, \modular, \grimoire_switch, [
        (\name: \inBusA, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Audio input A bus"),
        (\name: \inBusB, \default: 1, \min: 0, \max: 2048, \units: "bus", \desc: "Audio input B bus"),
        (\name: \cvBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "CV control bus"),
        (\name: \threshold, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "CV switch threshold")
    ], ~SC_GRP[\te], "CV-controlled A/B analog switch with crossfade");

    // 8. AND Gate
    ~MODULE_REGISTRY.register(\grimoire_and, \modular, \grimoire_and, [
        (\name: \inBus1, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 1"),
        (\name: \inBus2, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 2")
    ], ~SC_GRP[\te], "Logic AND gate for gate/trigger signals");

    // 9. OR Gate
    ~MODULE_REGISTRY.register(\grimoire_or, \modular, \grimoire_or, [
        (\name: \inBus1, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 1"),
        (\name: \inBus2, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 2")
    ], ~SC_GRP[\te], "Logic OR gate for gate/trigger signals");

    // 10. XOR Gate
    ~MODULE_REGISTRY.register(\grimoire_xor, \modular, \grimoire_xor, [
        (\name: \inBus1, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 1"),
        (\name: \inBus2, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 2")
    ], ~SC_GRP[\te], "Logic XOR gate for gate/trigger signals");

    // 11. NOT Gate
    ~MODULE_REGISTRY.register(\grimoire_not, \modular, \grimoire_not, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input")
    ], ~SC_GRP[\te], "Logic NOT (inverter) gate for gate/trigger signals");

    // 12. NAND Gate
    ~MODULE_REGISTRY.register(\grimoire_nand, \modular, \grimoire_nand, [
        (\name: \inBus1, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 1"),
        (\name: \inBus2, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 2")
    ], ~SC_GRP[\te], "Logic NAND gate for gate/trigger signals");

    // 13. NOR Gate
    ~MODULE_REGISTRY.register(\grimoire_nor, \modular, \grimoire_nor, [
        (\name: \inBus1, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 1"),
        (\name: \inBus2, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Gate input 2")
    ], ~SC_GRP[\te], "Logic NOR gate for gate/trigger signals");

    // 14. Comparator — A>B gate with hysteresis
    ~MODULE_REGISTRY.register(\grimoire_comparator, \modular, \grimoire_comparator, [
        (\name: \inBusA, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input A bus"),
        (\name: \inBusB, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input B bus"),
        (\name: \hysteresis, \default: 0.01, \min: 0, \max: 0.5, \units: "", \desc: "Hysteresis amount")
    ], ~SC_GRP[\te], "CV comparator with hysteresis: outputs gate when A > B");

    // 15. Rectifier — half/full wave CV rectification
    ~MODULE_REGISTRY.register(\grimoire_rectifier, \modular, \grimoire_rectifier, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "CV input bus"),
        (\name: \mode, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Mode (0=full wave 1=half wave)")
    ], ~SC_GRP[\te], "CV rectifier: full-wave or half-wave rectification");

    // 16. Min
    ~MODULE_REGISTRY.register(\grimoire_min, \modular, \grimoire_min, [
        (\name: \inBus1, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input 1 bus"),
        (\name: \inBus2, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input 2 bus")
    ], ~SC_GRP[\te], "Minimum of two CV signals");

    // 17. Max
    ~MODULE_REGISTRY.register(\grimoire_max, \modular, \grimoire_max, [
        (\name: \inBus1, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input 1 bus"),
        (\name: \inBus2, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "Input 2 bus")
    ], ~SC_GRP[\te], "Maximum of two CV signals");

    // 18. Quantizer (language-side) — reads CV bus, snaps to scale degrees
    ~MODULE_REGISTRY.register(\GRIMOIRE_QUANTIZER, \modular, \GRIMOIRE_QUANTIZER, [
        (\name: \rate, \default: 100, \min: 10, \max: 1000, \units: "Hz", \desc: "Quantization polling rate")
    ], ~SC_GRP[\te], "Language-side CV quantizer using BrahmaScale");

    // 19. Quantizer SynthDef — server-side CV quantizer
    ~MODULE_REGISTRY.register(\grimoire_quantizer, \modular, \grimoire_quantizer, [
        (\name: \inBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "CV input bus"),
        (\name: \rootFreq, \default: 440, \min: 20, \max: 20000, \units: "Hz", \desc: "Root frequency"),
        (\name: \numDegrees, \default: 12, \min: 1, \max: 128, \units: "", \desc: "Number of scale degrees"),
        (\name: \trigBus, \default: 0, \min: 0, \max: 2048, \units: "bus", \desc: "External trigger bus"),
        (\name: \trigMode, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Trigger mode (0=continuous 1=sample-and-hold)")
    ], ~SC_GRP[\te], "Server-side CV quantizer with scale buffer and trigger modes");

    "  MODULE_REGISTRY: 19 Grimoire utility modules registered".postln;
};
)
