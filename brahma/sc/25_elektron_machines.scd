/*
  Phase 6: MAGNUM OPUS — Synthesis Machines
  AUTOMATON (Machinedrum), AZOTH_MINOR (Digitone), CHIMERA (RYTM)
  TRX, EFM, E12, GND, Arpeggiator, Performance Macros, Sample Layer
*/

(
// ==========================================
// 1. AUTOMATON TRX — 909-style analog drum machine
// ==========================================
// 6 drum types via Select.ar: kick, snare, hat, clap, tom, rim.
// Each uses synthesis techniques authentic to the original circuits.
SynthDef(\automaton_trx, {
    |outBus=0, type=0, freq=60, decay=0.5, tone=0.5,
     snap=0.5, vel=0.8, gate=1|

    var kick, snare, hat, clap, tom, rim, sig, env;

    // -- KICK (0): Sine body + pitch envelope + click transient
    kick = {
        var pitchEnv = EnvGen.ar(Env.perc(0.001, 0.07), gate) * freq * 3;
        var body = SinOsc.ar(freq + pitchEnv) * EnvGen.ar(Env.perc(0.001, decay.clip(0.05, 2)));
        var click = HPF.ar(
            WhiteNoise.ar * EnvGen.ar(Env.perc(0.0005, 0.003)),
            800
        ) * snap.clip(0, 1) * 0.5;
        (body + click).tanh;
    }.value;

    // -- SNARE (1): Sine body + bandpass noise + HPF noise component
    snare = {
        var body = SinOsc.ar(freq * 2.8) * EnvGen.ar(Env.perc(0.001, decay.clip(0.03, 0.4) * 0.5));
        var noise = BPF.ar(WhiteNoise.ar, 3000 + (tone * 5000), 0.6)
            * EnvGen.ar(Env.perc(0.001, decay.clip(0.03, 0.4)));
        var hpNoise = HPF.ar(WhiteNoise.ar, 6000) * EnvGen.ar(Env.perc(0.001, 0.05)) * snap.clip(0, 1) * 0.3;
        (body * 0.6) + (noise * 0.8) + hpNoise;
    }.value;

    // -- HAT (2): Bandpass filtered noise + HPF, short decay
    hat = {
        var src = Mix.fill(6, { |i|
            SinOsc.ar(2000 + (i * 731.3) + (tone * 2000)) * 0.15;
        });
        var noise = HPF.ar(src + (WhiteNoise.ar * 0.3), 4000 + (tone * 4000));
        noise * EnvGen.ar(Env.perc(0.001, decay.clip(0.01, 1.5)));
    }.value;

    // -- CLAP (3): Filtered noise with multi-attack for hand-clap character
    clap = {
        var noiseSource = BPF.ar(WhiteNoise.ar, 1200 + (tone * 2000), 0.7);
        // Multiple short attacks simulate multiple hands
        var multiAttack = Mix.fill(4, { |i|
            EnvGen.ar(Env.perc(0.001, 0.005), TDelay.kr(gate, i * 0.008)) * 0.3;
        });
        var tail = EnvGen.ar(Env.perc(0.005, decay.clip(0.05, 0.5)));
        noiseSource * (multiAttack + tail);
    }.value;

    // -- TOM (4): Sine with pitch sweep, similar to kick but higher
    tom = {
        var pitchEnv = EnvGen.ar(Env.perc(0.001, 0.05)) * freq * 1.5;
        var body = SinOsc.ar(freq + pitchEnv) * EnvGen.ar(Env.perc(0.001, decay.clip(0.05, 1.0)));
        var attack = HPF.ar(WhiteNoise.ar, 1000) * EnvGen.ar(Env.perc(0.0005, 0.005)) * snap.clip(0, 1) * 0.3;
        body + attack;
    }.value;

    // -- RIM (5): Short metallic click via high-frequency bandpass
    rim = {
        var click = BPF.ar(
            WhiteNoise.ar,
            800 + (tone * 3000),
            0.02
        ) * EnvGen.ar(Env.perc(0.0005, 0.01 + (decay.clip(0, 0.1) * 0.5)));
        var body = SinOsc.ar(freq * 6) * EnvGen.ar(Env.perc(0.0005, 0.005)) * 0.4;
        (click * 8) + body;
    }.value;

    // Select drum type
    sig = Select.ar(type.clip(0, 5).round, [kick, snare, hat, clap, tom, rim]);

    // Free synth when envelope completes
    EnvGen.ar(Env.perc(0.001, decay.clip(0.01, 2) + 0.1), gate, doneAction: 2);

    Out.ar(outBus, sig * vel.clip(0, 1));
}).add;

// ==========================================
// 2. AUTOMATON EFM — FM metal percussion
// ==========================================
// 2-operator FM with feedback for metallic transients:
// bells, gongs, cymbals, metallic hits.
SynthDef(\automaton_efm, {
    |outBus=0, freq=800, ratio=3.5, index=5, decay=0.3,
     feedback=0, vel=0.8, gate=1|

    var mod, car, fb, sig, env, modEnv;

    env = EnvGen.ar(Env.perc(0.001, decay.clip(0.01, 4)), gate, doneAction: 2);

    // Modulator envelope decays faster for metallic transient character
    modEnv = EnvGen.ar(Env.perc(0.0005, decay.clip(0.01, 4) * 0.7), gate);

    // Feedback path
    fb = LocalIn.ar(1) * feedback.clip(0, 3);

    // Modulator: carrier frequency * ratio, scaled by index
    mod = SinOsc.ar(freq * ratio.clip(0.25, 16) + fb)
        * freq * ratio * index.clip(0, 20)
        * modEnv;

    // Carrier
    car = SinOsc.ar(freq + mod);

    // Feed back the carrier for self-modulation
    LocalOut.ar(car * feedback.clip(0, 3));

    sig = car * env * vel.clip(0, 1);

    Out.ar(outBus, LeakDC.ar(sig.clip(-1, 1)));
}).add;

// ==========================================
// 3. AUTOMATON E12 — 12-bit sample emulation
// ==========================================
// PlayBuf with bit-crushing and sample rate reduction.
// Emulates classic 12-bit sampler character (SP-1200, E-mu vintage).
SynthDef(\automaton_e12, {
    |outBus=0, bufnum=0, rate=1.0, start=0, decay=1.0,
     lofi=0.5, vel=0.8, gate=1|

    var play, crushed, env;
    var bitDepth, srReduce;

    env = EnvGen.ar(Env.perc(0.001, decay.clip(0.01, 8)), gate, doneAction: 2);

    // Playback from buffer
    play = PlayBuf.ar(1, bufnum,
        rate: rate.clip(-4, 4) * BufRateScale.kr(bufnum),
        startPos: start.clip(0, 1) * BufFrames.kr(bufnum),
        loop: 0
    );

    // Lo-fi degradation chain:
    // Bit depth: 16 bits at lofi=0 down to 4 bits at lofi=1
    bitDepth = lofi.clip(0, 1).linlin(0, 1, 16, 4);

    // Sample rate reduction: full SR at lofi=0 down to ~4kHz at lofi=1
    srReduce = lofi.clip(0, 1).linlin(0, 1, SampleRate.ir, 4000);

    // Latch for sample rate reduction, then bit-crush by rounding
    crushed = Latch.ar(play, Impulse.ar(srReduce));
    crushed = (crushed * (2 ** bitDepth)).round / (2 ** bitDepth);

    Out.ar(outBus, crushed * env * vel.clip(0, 1));
}).add;

// ==========================================
// 4. AUTOMATON GND — Noise machine percussion
// ==========================================
// Filtered noise percussion with selectable noise source.
// Bandpass envelope shaping for tuned noise drums.
SynthDef(\automaton_gnd, {
    |outBus=0, freq=1000, bw=0.5, decay=0.2, type=0,
     vel=0.8, gate=1|

    var noise, filtered, env;

    env = EnvGen.ar(Env.perc(0.001, decay.clip(0.005, 4)), gate, doneAction: 2);

    // Noise source selection: 0=white, 1=pink, 2=crackle
    noise = Select.ar(type.clip(0, 2).round, [
        WhiteNoise.ar,
        PinkNoise.ar,
        Crackle.ar(1.5 + (bw * 0.4))  // Chaotic noise; param affects density
    ]);

    // Bandpass filter with envelope-controlled center frequency
    filtered = BPF.ar(
        noise,
        freq.clip(20, 20000),
        bw.clip(0.01, 2)   // Bandwidth as reciprocal Q
    );

    // Boost narrow BPF output
    filtered = filtered * 4;

    Out.ar(outBus, filtered * env * vel.clip(0, 1));
}).add;

// ==========================================
// 5. AZOTH_MINOR ARP — Arpeggiator (audio-rate clock)
// ==========================================
// Outputs a control-rate note offset CV based on arpeggiator position.
// mode selects direction; rate sets speed in pulses per beat.
// Designed to drive other SynthDefs via control bus patching.
SynthDef(\azoth_minor_arp, {
    |outBus=0, trigBus=0, rate=8, mode=0, octaves=2|

    var trig, step, numSteps, offset;
    var upStep, downStep, upDownStep, randomStep;

    // External trigger or self-clocked
    trig = Select.ar(
        (trigBus > 0).asInteger,
        [
            Impulse.ar(rate.clip(0.5, 64)),
            In.ar(trigBus, 1)
        ]
    );

    numSteps = (octaves.clip(1, 4) * 12).asInteger;

    // Step counter
    step = Stepper.ar(trig, 0, 0, numSteps - 1);

    // Up: 0, 1, 2, ..., N-1
    upStep = step;

    // Down: N-1, N-2, ..., 0
    downStep = numSteps - 1 - step;

    // Up-Down: triangle pattern
    upDownStep = ((step * 2).fold(0, (numSteps - 1) * 2) / 2).round;

    // Random: sample-and-hold random per trigger
    randomStep = TIRand.ar(0, numSteps - 1, trig);

    // Mode selection: 0=up, 1=down, 2=upDown, 3=random
    offset = Select.ar(mode.clip(0, 3).round, [
        upStep,
        downStep,
        upDownStep,
        randomStep
    ]);

    // Output: semitone offset (0 to numSteps-1)
    // Downstream synths convert this to frequency via .midicps
    Out.ar(outBus, offset);
}).add;

// ==========================================
// 6. CHIMERA SAMPLE LAYER — Analog + sample hybrid
// ==========================================
// Layers a synthesis voice with a sample playback for RYTM-style hybrid drums.
// synthBus carries the analog component; bufnum provides the digital sample.
SynthDef(\chimera_sample_layer, {
    |outBus=0, synthBus=0, bufnum=0, gate=1, vel=0.8,
     synthLevel=0.7, sampleLevel=0.5,
     sampleRate=1.0, sampleStart=0, sampleDecay=1.0,
     filterFreq=8000, filterRes=1|

    var synthSig, sampleSig, mix, env, filt;

    env = EnvGen.ar(Env.asr(0.001, 1, 0.01), gate, doneAction: 2);

    // Analog component from synthesis bus
    synthSig = In.ar(synthBus, 1) * synthLevel.clip(0, 2);

    // Sample component
    sampleSig = PlayBuf.ar(1, bufnum,
        rate: sampleRate.clip(0.25, 4) * BufRateScale.kr(bufnum),
        startPos: sampleStart.clip(0, 1) * BufFrames.kr(bufnum),
        loop: 0
    ) * EnvGen.ar(Env.perc(0.001, sampleDecay.clip(0.01, 8)), gate)
      * sampleLevel.clip(0, 2);

    // Layer mix
    mix = synthSig + sampleSig;

    // Shared filter
    filt = RLPF.ar(mix,
        filterFreq.clip(20, 20000),
        (1 / filterRes.clip(0.5, 20)).clip(0.01, 1)
    );

    Out.ar(outBus, filt * env * vel.clip(0, 1));
}).add;

// ==========================================
// CHIMERA PERFORMANCE MACROS — Language-side
// ==========================================
// 8 macro knobs, each mappable to multiple parameter targets.
// Inspired by Elektron RYTM performance mode for expressive one-knob control.
~CHIMERA_MACROS = (
    macros: Array.fill(8, { (targets: List.new, value: 0.5) }),

    // Set a macro value and propagate to all assigned targets
    setMacro: { |self, idx, val|
        var macro;
        idx = idx.clip(0, 7);
        macro = self[\macros][idx];
        macro[\value] = val.clip(0, 1);
        macro[\targets].do({ |target|
            // target: (bus: Bus, min: 0, max: 1, curve: \lin)
            var mapped;
            if(target[\curve] == \exp) {
                mapped = val.clip(0.001, 1).linexp(0, 1, target[\min], target[\max]);
            } {
                mapped = val.linlin(0, 1, target[\min], target[\max]);
            };
            target[\bus].set(mapped);
        });
    },

    // Assign a bus target to a macro with min/max range
    assignTarget: { |self, macroIdx, bus, min=0, max=1, curve=\lin|
        macroIdx = macroIdx.clip(0, 7);
        self[\macros][macroIdx][\targets].add((
            bus: bus,
            min: min,
            max: max,
            curve: curve ? \lin
        ));
        "CHIMERA MACRO %: Assigned target (bus: %, range: %..%)".format(
            macroIdx, bus, min, max
        ).postln;
    },

    // Remove all targets from a macro
    clearMacro: { |self, macroIdx|
        macroIdx = macroIdx.clip(0, 7);
        self[\macros][macroIdx][\targets] = List.new;
        self[\macros][macroIdx][\value] = 0.5;
        "CHIMERA MACRO %: Cleared".format(macroIdx).postln;
    },

    // Remove a specific target by index
    removeTarget: { |self, macroIdx, targetIdx|
        macroIdx = macroIdx.clip(0, 7);
        if(targetIdx < self[\macros][macroIdx][\targets].size) {
            self[\macros][macroIdx][\targets].removeAt(targetIdx);
        };
    },

    // Get current state for visualization
    getState: { |self|
        self[\macros].collect({ |m, i|
            (idx: i, value: m[\value], numTargets: m[\targets].size);
        });
    }
);

// ==========================================
// OSC RESPONDERS — /automaton/*
// ==========================================

// TRX trigger: /automaton/trx <type:int> <freq:float> <decay:float> <tone:float> <snap:float> <vel:float>
OSCdef(\automaton_trx_trig, { |msg|
    var type = msg[1].asInteger;
    var freq = msg[2] !? _.asFloat ?? 60;
    var decay = msg[3] !? _.asFloat ?? 0.5;
    var tone = msg[4] !? _.asFloat ?? 0.5;
    var snap = msg[5] !? _.asFloat ?? 0.5;
    var vel = msg[6] !? _.asFloat ?? 0.8;
    Synth(\automaton_trx, [
        \outBus, ~AUTOMATON_BUS ? 0,
        \type, type, \freq, freq, \decay, decay,
        \tone, tone, \snap, snap, \vel, vel, \gate, 1
    ], target: ~SC_GRP[\te]);
    ~VISUAL_CORTEX.target.sendMsg("/automaton/trx/state", type, freq, vel);
}, "/automaton/trx");

// EFM trigger: /automaton/efm <freq:float> <ratio:float> <index:float> <decay:float> <feedback:float> <vel:float>
OSCdef(\automaton_efm_trig, { |msg|
    var freq = msg[1] !? _.asFloat ?? 800;
    var ratio = msg[2] !? _.asFloat ?? 3.5;
    var index = msg[3] !? _.asFloat ?? 5;
    var decay = msg[4] !? _.asFloat ?? 0.3;
    var feedback = msg[5] !? _.asFloat ?? 0;
    var vel = msg[6] !? _.asFloat ?? 0.8;
    Synth(\automaton_efm, [
        \outBus, ~AUTOMATON_BUS ? 0,
        \freq, freq, \ratio, ratio, \index, index,
        \decay, decay, \feedback, feedback, \vel, vel, \gate, 1
    ], target: ~SC_GRP[\te]);
    ~VISUAL_CORTEX.target.sendMsg("/automaton/efm/state", freq, ratio, vel);
}, "/automaton/efm");

// E12 trigger: /automaton/e12 <bufnum:int> <rate:float> <start:float> <decay:float> <lofi:float> <vel:float>
OSCdef(\automaton_e12_trig, { |msg|
    var bufnum = msg[1].asInteger;
    var rate = msg[2] !? _.asFloat ?? 1.0;
    var start = msg[3] !? _.asFloat ?? 0;
    var decay = msg[4] !? _.asFloat ?? 1.0;
    var lofi = msg[5] !? _.asFloat ?? 0.5;
    var vel = msg[6] !? _.asFloat ?? 0.8;
    Synth(\automaton_e12, [
        \outBus, ~AUTOMATON_BUS ? 0,
        \bufnum, bufnum, \rate, rate, \start, start,
        \decay, decay, \lofi, lofi, \vel, vel, \gate, 1
    ], target: ~SC_GRP[\te]);
    ~VISUAL_CORTEX.target.sendMsg("/automaton/e12/state", bufnum, lofi, vel);
}, "/automaton/e12");

// GND trigger: /automaton/gnd <freq:float> <bw:float> <decay:float> <type:int> <vel:float>
OSCdef(\automaton_gnd_trig, { |msg|
    var freq = msg[1] !? _.asFloat ?? 1000;
    var bw = msg[2] !? _.asFloat ?? 0.5;
    var decay = msg[3] !? _.asFloat ?? 0.2;
    var type = msg[4] !? _.asInteger ?? 0;
    var vel = msg[5] !? _.asFloat ?? 0.8;
    Synth(\automaton_gnd, [
        \outBus, ~AUTOMATON_BUS ? 0,
        \freq, freq, \bw, bw, \decay, decay,
        \type, type, \vel, vel, \gate, 1
    ], target: ~SC_GRP[\te]);
    ~VISUAL_CORTEX.target.sendMsg("/automaton/gnd/state", freq, type, vel);
}, "/automaton/gnd");

// ==========================================
// OSC RESPONDERS — /azoth_minor/*
// ==========================================

// Arp params: /azoth_minor/arp <rate:float> <mode:int> <octaves:int>
OSCdef(\azoth_minor_arp_ctrl, { |msg|
    var rate = msg[1] !? _.asFloat ?? 8;
    var mode = msg[2] !? _.asInteger ?? 0;
    var octaves = msg[3] !? _.asInteger ?? 2;
    ~AZOTH_MINOR_NODES !? { |nodes|
        nodes[\arp] !? { |syn|
            syn.set(\rate, rate.clip(0.5, 64), \mode, mode.clip(0, 3), \octaves, octaves.clip(1, 4));
        };
    };
    ~VISUAL_CORTEX.target.sendMsg("/azoth_minor/arp/state", rate, mode, octaves);
}, "/azoth_minor/arp");

// ==========================================
// OSC RESPONDERS — /chimera/*
// ==========================================

// Macro control: /chimera/macro <macroIdx:int> <value:float>
OSCdef(\chimera_macro_set, { |msg|
    var idx = msg[1].asInteger;
    var val = msg[2].asFloat;
    ~CHIMERA_MACROS.setMacro(idx, val);
    ~VISUAL_CORTEX.target.sendMsg("/chimera/macro/state", idx, val);
}, "/chimera/macro");

// Macro assign: /chimera/macro/assign <macroIdx:int> <busIdx:int> <min:float> <max:float>
OSCdef(\chimera_macro_assign, { |msg|
    var macroIdx = msg[1].asInteger;
    var busIdx = msg[2].asInteger;
    var min = msg[3] !? _.asFloat ?? 0;
    var max = msg[4] !? _.asFloat ?? 1;
    var curve = msg[5] !? _.asSymbol ?? \lin;
    var bus = Bus(\control, busIdx, 1, s);
    ~CHIMERA_MACROS.assignTarget(macroIdx, bus, min, max, curve);
}, "/chimera/macro/assign");

// Macro clear: /chimera/macro/clear <macroIdx:int>
OSCdef(\chimera_macro_clear, { |msg|
    ~CHIMERA_MACROS.clearMacro(msg[1].asInteger);
}, "/chimera/macro/clear");

// Sample layer trigger: /chimera/layer <bufnum:int> <synthBus:int> <vel:float> <synthLevel:float> <sampleLevel:float>
OSCdef(\chimera_layer_trig, { |msg|
    var bufnum = msg[1].asInteger;
    var synthBus = msg[2] !? _.asInteger ?? 0;
    var vel = msg[3] !? _.asFloat ?? 0.8;
    var synthLevel = msg[4] !? _.asFloat ?? 0.7;
    var sampleLevel = msg[5] !? _.asFloat ?? 0.5;
    Synth(\chimera_sample_layer, [
        \outBus, ~CHIMERA_BUS ? 0,
        \synthBus, synthBus,
        \bufnum, bufnum,
        \vel, vel,
        \synthLevel, synthLevel,
        \sampleLevel, sampleLevel,
        \gate, 1
    ], target: ~SC_GRP[\te]);
    ~VISUAL_CORTEX.target.sendMsg("/chimera/layer/state", bufnum, vel);
}, "/chimera/layer");

// ==========================================
// Node and bus holders for live instances
// ==========================================
~AUTOMATON_BUS = ~AUTOMATON_BUS ? 0;
~AZOTH_MINOR_NODES = ~AZOTH_MINOR_NODES ? (arp: nil);
~CHIMERA_BUS = ~CHIMERA_BUS ? 0;

"--- BRAHMA: MAGNUM OPUS Synthesis Machines Online (6 machines) ---".postln;
"  AUTOMATON: TRX (909) | EFM (FM Metal) | E12 (12-bit) | GND (Noise)".postln;
"  AZOTH_MINOR: Arpeggiator | CHIMERA: Sample Layer + Performance Macros".postln;
)
