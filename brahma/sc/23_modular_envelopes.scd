/*
  Phase 23: NIGREDO (The Blackening) — Modular Envelopes
  ADSR, AD, AR, Multi-stage, Function Generator, Looping Envelope

  Control-rate envelope generators for modular patching. All outputs go
  to control buses via Out.kr, suitable for driving VCAs, VCFs, and any
  parameter that accepts CV input.

  Naming follows the alchemical Nigredo phase: the initial stage of
  dissolution where raw material is broken down — envelopes shape the
  temporal boundaries of sound's birth and death.

  Modules:
    1. NIGREDO_ADSR     — Standard Attack-Decay-Sustain-Release
    2. NIGREDO_AD       — Attack-Decay (trigger mode, no sustain)
    3. NIGREDO_AR       — Attack-Release (gate mode, no decay/sustain)
    4. NIGREDO_MULTI    — Multi-stage (up to 8 segments with loop points)
    5. NIGREDO_FUNCTION — MATHS-style function generator (rise/fall/cycle)
    6. NIGREDO_LOOPING  — Looping AR envelope with auto-retrigger
*/

(
// ==========================================
// 1. NIGREDO_ADSR — Standard ADSR Envelope
// ==========================================
// Classic four-stage envelope. Gate high starts attack; gate low starts
// release from current level. Curve parameter shapes all segments:
// negative values = logarithmic, 0 = linear, positive = exponential.
SynthDef(\nigredo_adsr, {
    |outBus=0, gate=1, atk=0.01, dec=0.3, sus=0.7, rel=0.3, curve=(-4)|

    var env;

    atk = atk.clip(0.001, 30);
    dec = dec.clip(0.001, 30);
    sus = sus.clip(0, 1);
    rel = rel.clip(0.001, 30);
    curve = curve.clip(-8, 8);

    env = EnvGen.kr(
        Env.adsr(atk, dec, sus, rel, curve: curve),
        gate,
        doneAction: 0
    );

    Out.kr(outBus, env);
}).add;

// ==========================================
// 2. NIGREDO_AD — Attack-Decay Envelope
// ==========================================
// Trigger-mode envelope: fires a single attack-decay cycle on each
// trigger input, regardless of trigger duration. No sustain phase.
// Suitable for percussive transients and pluck-style articulations.
SynthDef(\nigredo_ad, {
    |outBus=0, trig=0, atk=0.01, dec=0.3, curve=(-4)|

    var env;

    atk = atk.clip(0.001, 30);
    dec = dec.clip(0.001, 30);
    curve = curve.clip(-8, 8);

    env = EnvGen.kr(
        Env.perc(atk, dec, 1.0, curve),
        Trig1.kr(trig, 0.001),
        doneAction: 0
    );

    Out.kr(outBus, env);
}).add;

// ==========================================
// 3. NIGREDO_AR — Attack-Release Envelope
// ==========================================
// Gate-mode envelope: attack phase while gate is high, release phase
// when gate goes low. No intermediate decay or sustain — the signal
// rises to full level and holds until released. Useful for organ-style
// articulation and pad sounds.
SynthDef(\nigredo_ar, {
    |outBus=0, gate=1, atk=0.01, rel=0.3, curve=(-4)|

    var env;

    atk = atk.clip(0.001, 30);
    rel = rel.clip(0.001, 30);
    curve = curve.clip(-8, 8);

    env = EnvGen.kr(
        Env(
            [0, 1, 0],
            [atk, rel],
            [curve, curve],
            releaseNode: 1  // sustain at peak until gate off
        ),
        gate,
        doneAction: 0
    );

    Out.kr(outBus, env);
}).add;

// ==========================================
// 4. NIGREDO_MULTI — Multi-Stage Envelope
// ==========================================
// Up to 8 segments with configurable loop points. Levels and times are
// NamedControl arrays for flexible multi-breakpoint envelopes. The loop
// region (loopStart to loopEnd) repeats while the gate is held high;
// when the gate goes low, playback jumps to the segment after loopEnd
// and proceeds to the final level.
//
// Segments: level0 -> level1 (over time0) -> level2 (over time1) -> ...
// Set loopStart = loopEnd = 0 to disable looping.
SynthDef(\nigredo_multi, {
    |outBus=0, gate=1,
     level0=0, level1=1, level2=0.7, level3=0.5,
     level4=0.3, level5=0.2, level6=0.1, level7=0.05, level8=0,
     time0=0.01, time1=0.1, time2=0.1, time3=0.1,
     time4=0.1, time5=0.1, time6=0.1, time7=0.1,
     loopStart=0, loopEnd=0|

    var levels, times, env;
    var loopNode, releaseNode;

    levels = [
        level0.clip(0, 1), level1.clip(0, 1), level2.clip(0, 1),
        level3.clip(0, 1), level4.clip(0, 1), level5.clip(0, 1),
        level6.clip(0, 1), level7.clip(0, 1), level8.clip(0, 1)
    ];

    times = [
        time0.clip(0.001, 30), time1.clip(0.001, 30),
        time2.clip(0.001, 30), time3.clip(0.001, 30),
        time4.clip(0.001, 30), time5.clip(0.001, 30),
        time6.clip(0.001, 30), time7.clip(0.001, 30)
    ];

    loopStart = loopStart.clip(0, 7).round;
    loopEnd = loopEnd.clip(0, 7).round;

    // Build envelope with optional loop and release nodes
    // loopNode: where to loop back to while gate is held
    // releaseNode: where to jump on gate release
    loopNode = Select.kr((loopStart > 0) * (loopEnd > loopStart), [
        -1,            // no loop
        loopStart      // loop from this node
    ]);

    releaseNode = Select.kr((loopEnd > 0) * (loopEnd > loopStart), [
        -1,            // no explicit release node
        loopEnd        // release from this node
    ]);

    env = EnvGen.kr(
        Env(
            levels,
            times,
            \lin,
            releaseNode: if(loopEnd > loopStart, { loopEnd }, { -1 }),
            loopNode: if(loopStart > 0, { loopStart }, { -1 })
        ),
        gate,
        doneAction: 0
    );

    Out.kr(outBus, env);
}).add;

// ==========================================
// 5. NIGREDO_FUNCTION — Function Generator (MATHS-style)
// ==========================================
// Rise/fall function generator with configurable shape and cycle mode.
// In one-shot mode, a trigger fires a single rise-then-fall contour.
// In cycle mode, the function repeats continuously as an LFO.
// End-of-rise (eorBus) and end-of-cycle (eocBus) trigger outputs
// enable downstream patching and cascading.
SynthDef(\nigredo_function, {
    |outBus=0, trig=0, gate=1, rise=0.1, fall=0.3, shape=0, cycle=0,
     eorBus=0, eocBus=0|

    var modRise, modFall, reTrig, env, phase, sig;
    var risePortion, risePhase, fallPhase, inRise;
    var curveAmt, shapedRise, shapedFall;
    var eor, eoc;

    rise = rise.clip(0.001, 25);
    fall = fall.clip(0.001, 25);
    curveAmt = shape.clip(-8, 8);
    cycle = cycle.clip(0, 1);

    reTrig = Trig1.kr(trig, 0.001);

    // One-shot mode: standard two-segment envelope
    env = EnvGen.kr(
        Env(
            [0, 1, 0],
            [rise, fall],
            [curveAmt, curveAmt.neg]
        ),
        reTrig + (gate * Impulse.kr(0)),
        doneAction: 0
    );

    // Cycling mode: phasor-based continuous generation
    phase = Phasor.kr(
        reTrig,
        (1 / ((rise + fall) * ControlRate.ir)).clip(0, 1),
        0, 1
    );

    risePortion = (rise / (rise + fall)).clip(0.001, 0.999);
    risePhase = (phase / risePortion).clip(0, 1);
    fallPhase = ((phase - risePortion) / (1 - risePortion)).clip(0, 1);
    inRise = (phase < risePortion);

    // Apply curve shaping
    shapedRise = Select.kr((curveAmt.abs > 0.01).asInteger, [
        risePhase,
        risePhase.lincurve(0, 1, 0, 1, curveAmt)
    ]);
    shapedFall = Select.kr((curveAmt.abs > 0.01).asInteger, [
        1 - fallPhase,
        fallPhase.lincurve(0, 1, 1, 0, curveAmt.neg)
    ]);

    sig = (shapedRise * inRise) + (shapedFall * (1 - inRise));

    // Select between one-shot and cycling modes
    sig = Select.kr(cycle.round, [env, sig]);

    // End-of-rise trigger: fires when phase crosses the rise/fall boundary
    eor = Trig1.kr(phase > risePortion, 0.001);

    // End-of-cycle trigger: fires when phase wraps back to start
    eoc = Trig1.kr(phase < 0.01, 0.001);

    Out.kr(eorBus, eor);
    Out.kr(eocBus, eoc);
    Out.kr(outBus, sig);
}).add;

// ==========================================
// 6. NIGREDO_LOOPING — Looping AR Envelope
// ==========================================
// Attack-release envelope with auto-retrigger. When loop is enabled (1)
// and gate is high, the envelope continuously cycles: attack to peak,
// release to zero, then retrigger. Effectively an envelope-shaped LFO
// whose rate is determined by attack + release times. When loop is
// disabled, behaves as a standard AR envelope.
SynthDef(\nigredo_looping, {
    |outBus=0, gate=1, atk=0.01, rel=0.3, loop=0|

    var env, loopTrig, sig;

    atk = atk.clip(0.001, 30);
    rel = rel.clip(0.001, 30);
    loop = loop.clip(0, 1);

    // In loop mode, generate a repeating trigger at the AR cycle rate
    // The impulse frequency is 1 / (atk + rel)
    loopTrig = Impulse.kr((1 / (atk + rel)).clip(0.01, 1000)) * loop * gate;

    // Combine external gate with loop retrigger
    env = EnvGen.kr(
        Env.perc(atk, rel, 1.0, -4),
        gate + loopTrig,
        doneAction: 0
    );

    // Mute output when gate is low
    sig = env * gate.lag(0.001);

    Out.kr(outBus, sig);
}).add;

"--- BRAHMA: NIGREDO Modular Envelopes Online (6 modules) ---".postln;
"  NIGREDO_ADSR | NIGREDO_AD | NIGREDO_AR".postln;
"  NIGREDO_MULTI | NIGREDO_FUNCTION | NIGREDO_LOOPING".postln;

// ==========================================
// PATCH BAY REGISTRATION — Modular Envelopes
// ==========================================
[
    [\nigredo_adsr, [
        [\atk, "Attack time"], [\dec, "Decay time"],
        [\sus, "Sustain level"], [\rel, "Release time"],
        [\curve, "Curve shape"]
    ]],
    [\nigredo_ad, [
        [\atk, "Attack time"], [\dec, "Decay time"], [\curve, "Curve shape"]
    ]],
    [\nigredo_ar, [
        [\atk, "Attack time"], [\rel, "Release time"], [\curve, "Curve shape"]
    ]],
    [\nigredo_function, [
        [\rise, "Rise time"], [\fall, "Fall time"],
        [\shape, "Curve shape"], [\cycle, "Cycle mode"]
    ]],
    [\nigredo_looping, [
        [\atk, "Attack time"], [\rel, "Release time"], [\loop, "Loop enable"]
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

// ==========================================
// MODULE REGISTRY REGISTRATION — Modular Envelopes
// ==========================================

// --- MODULE REGISTRY REGISTRATION: NIGREDO_ADSR ---
if(~MODULE_REGISTRY.notNil) {
    ~MODULE_REGISTRY.register(\nigredo_adsr, \modular, \nigredo_adsr, [
        (\name: \atk, \default: 0.01, \min: 0.001, \max: 30, \units: "s", \desc: "Attack time"),
        (\name: \dec, \default: 0.3, \min: 0.001, \max: 30, \units: "s", \desc: "Decay time"),
        (\name: \sus, \default: 0.7, \min: 0, \max: 1, \units: "", \desc: "Sustain level"),
        (\name: \rel, \default: 0.3, \min: 0.001, \max: 30, \units: "s", \desc: "Release time"),
        (\name: \curve, \default: -4, \min: -8, \max: 8, \units: "", \desc: "Curve shape"),
    ], ~SC_GRP[\te], "Standard ADSR envelope with configurable curve shape");
};

// --- MODULE REGISTRY REGISTRATION: NIGREDO_AD ---
if(~MODULE_REGISTRY.notNil) {
    ~MODULE_REGISTRY.register(\nigredo_ad, \modular, \nigredo_ad, [
        (\name: \atk, \default: 0.01, \min: 0.001, \max: 30, \units: "s", \desc: "Attack time"),
        (\name: \dec, \default: 0.3, \min: 0.001, \max: 30, \units: "s", \desc: "Decay time"),
        (\name: \curve, \default: -4, \min: -8, \max: 8, \units: "", \desc: "Curve shape"),
    ], ~SC_GRP[\te], "Trigger-mode attack-decay envelope for percussive transients");
};

// --- MODULE REGISTRY REGISTRATION: NIGREDO_AR ---
if(~MODULE_REGISTRY.notNil) {
    ~MODULE_REGISTRY.register(\nigredo_ar, \modular, \nigredo_ar, [
        (\name: \atk, \default: 0.01, \min: 0.001, \max: 30, \units: "s", \desc: "Attack time"),
        (\name: \rel, \default: 0.3, \min: 0.001, \max: 30, \units: "s", \desc: "Release time"),
        (\name: \curve, \default: -4, \min: -8, \max: 8, \units: "", \desc: "Curve shape"),
    ], ~SC_GRP[\te], "Gate-mode attack-release envelope for organ-style articulation");
};

// --- MODULE REGISTRY REGISTRATION: NIGREDO_MULTI ---
if(~MODULE_REGISTRY.notNil) {
    ~MODULE_REGISTRY.register(\nigredo_multi, \modular, \nigredo_multi, [
        (\name: \level0, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Segment 0 level (start)"),
        (\name: \level1, \default: 1, \min: 0, \max: 1, \units: "", \desc: "Segment 1 level"),
        (\name: \level2, \default: 0.7, \min: 0, \max: 1, \units: "", \desc: "Segment 2 level"),
        (\name: \level3, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Segment 3 level"),
        (\name: \level4, \default: 0.3, \min: 0, \max: 1, \units: "", \desc: "Segment 4 level"),
        (\name: \level5, \default: 0.2, \min: 0, \max: 1, \units: "", \desc: "Segment 5 level"),
        (\name: \level6, \default: 0.1, \min: 0, \max: 1, \units: "", \desc: "Segment 6 level"),
        (\name: \level7, \default: 0.05, \min: 0, \max: 1, \units: "", \desc: "Segment 7 level"),
        (\name: \level8, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Segment 8 level (end)"),
        (\name: \time0, \default: 0.01, \min: 0.001, \max: 30, \units: "s", \desc: "Segment 0-1 time"),
        (\name: \time1, \default: 0.1, \min: 0.001, \max: 30, \units: "s", \desc: "Segment 1-2 time"),
        (\name: \time2, \default: 0.1, \min: 0.001, \max: 30, \units: "s", \desc: "Segment 2-3 time"),
        (\name: \time3, \default: 0.1, \min: 0.001, \max: 30, \units: "s", \desc: "Segment 3-4 time"),
        (\name: \time4, \default: 0.1, \min: 0.001, \max: 30, \units: "s", \desc: "Segment 4-5 time"),
        (\name: \time5, \default: 0.1, \min: 0.001, \max: 30, \units: "s", \desc: "Segment 5-6 time"),
        (\name: \time6, \default: 0.1, \min: 0.001, \max: 30, \units: "s", \desc: "Segment 6-7 time"),
        (\name: \time7, \default: 0.1, \min: 0.001, \max: 30, \units: "s", \desc: "Segment 7-8 time"),
        (\name: \loopStart, \default: 0, \min: 0, \max: 7, \units: "", \desc: "Loop start segment"),
        (\name: \loopEnd, \default: 0, \min: 0, \max: 7, \units: "", \desc: "Loop end segment"),
    ], ~SC_GRP[\te], "Multi-stage envelope with up to 8 segments and optional loop region");
};

// --- MODULE REGISTRY REGISTRATION: NIGREDO_FUNCTION ---
if(~MODULE_REGISTRY.notNil) {
    ~MODULE_REGISTRY.register(\nigredo_function, \modular, \nigredo_function, [
        (\name: \rise, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "Rise time"),
        (\name: \fall, \default: 0.3, \min: 0.001, \max: 25, \units: "s", \desc: "Fall time"),
        (\name: \shape, \default: 0, \min: -8, \max: 8, \units: "", \desc: "Curve shape"),
        (\name: \cycle, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Cycle mode (0=one-shot, 1=loop)"),
    ], ~SC_GRP[\te], "MATHS-style function generator with rise/fall/cycle and EOR/EOC triggers");
};

// --- MODULE REGISTRY REGISTRATION: NIGREDO_LOOPING ---
if(~MODULE_REGISTRY.notNil) {
    ~MODULE_REGISTRY.register(\nigredo_looping, \modular, \nigredo_looping, [
        (\name: \atk, \default: 0.01, \min: 0.001, \max: 30, \units: "s", \desc: "Attack time"),
        (\name: \rel, \default: 0.3, \min: 0.001, \max: 30, \units: "s", \desc: "Release time"),
        (\name: \loop, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Loop enable (0=off, 1=on)"),
    ], ~SC_GRP[\te], "Looping AR envelope with auto-retrigger for envelope-shaped LFO");
};
)
