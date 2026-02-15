/*
  Phase 17: Hermetic Function Generators
  Make Noise behavioral clones — circuit-accurate function generator modeling

  Modules:
    1. HERMETIC DUAL    — MATHS clone (dual function gen + attenuverters)
    2. HERMETIC QUAD    — PoliMATHS clone (4-channel cascading function gen)
    3. HERMETIC MONO    — Function clone (single channel function gen)
    4. HERMETIC CONTOUR — Contour clone (ASR contour generator)

  All SynthDefs follow Brahma standard interface:
    outBus, inBus, gate, trig + module-specific params.
  Control bus outputs for EOR/EOC triggers enable inter-module patching
  via the Brahma Patch Bay (08_patch_bay.scd).

  Rise/fall times: 0.001s to 25s (matching hardware voltage ranges)
  Curve shapes: -8 (logarithmic) through 0 (linear) to +8 (exponential)
*/

(
// ==========================================
// HELPER: Function Generator Core
// ==========================================
// Shared envelope engine used by all hermetic modules.
// Generates a single rise/fall function with configurable shape,
// cycle mode, and trigger outputs. Returns [signal, eor, eoc].
//
// Why a SynthDef and not a function: we need audio-rate envelope
// generation with proper trigger detection, which requires UGens.
// Each channel instantiates this core or inlines equivalent logic.

// ==========================================
// 1. HERMETIC DUAL — MATHS Clone
// ==========================================
// Channels 1 & 4: full function generators (rise, fall, shape, cycle, EOR/EOC)
// Channels 2 & 3: simple attenuverters (bipolar scaling of input)
// Outputs: ch1, ch4, ch2, ch3, sum (ch1+ch4), or (max of ch1,ch4)
SynthDef(\hermetic_dual, {
    |outBus=0, inBus=0, gate=1, trig=0,

     // Channel 1 (full function generator)
     ch1_rise=0.1,          // 0.001..25 seconds
     ch1_fall=0.3,          // 0.001..25 seconds
     ch1_curve=0.0,         // -8..+8 (neg=log, 0=lin, pos=exp)
     ch1_cycle=0,           // 0=one-shot, 1=cycling (LFO mode)
     ch1_trig=0,            // trigger input for channel 1
     ch1_rise_cv=0.0,       // -1..+1 CV modulation of rise time
     ch1_fall_cv=0.0,       // -1..+1 CV modulation of fall time
     ch1_level=1.0,         // 0..1 output level

     // Channel 4 (full function generator)
     ch4_rise=0.1,
     ch4_fall=0.3,
     ch4_curve=0.0,
     ch4_cycle=0,
     ch4_trig=0,
     ch4_rise_cv=0.0,
     ch4_fall_cv=0.0,
     ch4_level=1.0,

     // Channel 2 (attenuverter)
     ch2_input=0.0,         // signal input (or use inBus)
     ch2_atten=0.5,         // -1..+1 attenuverter amount

     // Channel 3 (attenuverter)
     ch3_input=0.0,
     ch3_atten=0.5,

     // Trigger output buses (control rate)
     ch1_eor_bus=0,         // end-of-rise trigger output
     ch1_eoc_bus=0,         // end-of-cycle trigger output
     ch4_eor_bus=0,
     ch4_eoc_bus=0|

    var ch1Sig, ch4Sig, ch2Sig, ch3Sig;
    var ch1Rise, ch1Fall, ch4Rise, ch4Fall;
    var ch1Env, ch4Env, ch1Phase, ch4Phase;
    var ch1Eor, ch1Eoc, ch4Eor, ch4Eoc;
    var ch1ReTrig, ch4ReTrig;
    var sumOut, orOut;
    var externalIn;

    externalIn = In.ar(inBus, 1);

    // --- Channel 1: Full Function Generator ---

    // CV-modulated rise/fall with safe clamping
    ch1Rise = (ch1_rise * (2 ** (ch1_rise_cv.clip(-1, 1) * 4))).clip(0.001, 25);
    ch1Fall = (ch1_fall * (2 ** (ch1_fall_cv.clip(-1, 1) * 4))).clip(0.001, 25);

    // Trigger logic: external trig OR cycle retrigger
    // In cycle mode, EOC feeds back to retrigger
    ch1ReTrig = Trig1.ar(ch1_trig + trig, 0.001);

    // Generate the function: rise then fall envelope
    // Using EnvGen with a custom two-segment envelope
    // Segment 1: 0 -> 1 over rise time (attack)
    // Segment 2: 1 -> 0 over fall time (release)
    ch1Env = EnvGen.ar(
        Env(
            [0, 1, 0],
            [ch1Rise, ch1Fall],
            [ch1_curve.clip(-8, 8), ch1_curve.clip(-8, 8).neg]
        ),
        ch1ReTrig + (gate * Impulse.ar(0)),
        doneAction: 0
    );

    // Cycle mode: use LFO-style continuous generation
    // Phasor-based approach for true cycling with variable shape
    ch1Phase = Phasor.ar(
        ch1ReTrig,
        (1 / ((ch1Rise + ch1Fall) * SampleRate.ir)).clip(0, 1),
        0, 1
    );

    // Shape the phase into rise/fall function
    // Rise portion: phase < rise/(rise+fall), Fall portion: remainder
    ch1Sig = {
        var risePortion = (ch1Rise / (ch1Rise + ch1Fall)).clip(0.001, 0.999);
        var risePhase = (ch1Phase / risePortion).clip(0, 1);
        var fallPhase = ((ch1Phase - risePortion) / (1 - risePortion)).clip(0, 1);
        var inRise = (ch1Phase < risePortion);

        // Apply curve shaping
        var curveAmt = ch1_curve.clip(-8, 8);
        var shapedRise = Select.ar((curveAmt.abs > 0.01).asInteger, [
            risePhase,  // linear
            risePhase.lincurve(0, 1, 0, 1, curveAmt)
        ]);
        var shapedFall = Select.ar((curveAmt.abs > 0.01).asInteger, [
            1 - fallPhase,  // linear
            fallPhase.lincurve(0, 1, 1, 0, curveAmt.neg)
        ]);

        (shapedRise * inRise) + (shapedFall * (1 - inRise));
    }.value;

    // Select between one-shot (EnvGen) and cycling (Phasor) modes
    ch1Sig = Select.ar(ch1_cycle.clip(0, 1), [ch1Env, ch1Sig]);
    ch1Sig = ch1Sig * ch1_level.clip(0, 1);

    // EOR/EOC trigger generation
    // EOR fires when signal crosses peak (end of rise)
    ch1Eor = {
        var risePortion = (ch1Rise / (ch1Rise + ch1Fall)).clip(0.001, 0.999);
        Trig1.kr(A2K.kr(ch1Phase) > risePortion, 0.001);
    }.value;

    // EOC fires when cycle completes (phase wraps)
    ch1Eoc = Trig1.kr(A2K.kr(ch1Phase) < 0.01, 0.001);

    Out.kr(ch1_eor_bus, ch1Eor);
    Out.kr(ch1_eoc_bus, ch1Eoc);

    // --- Channel 4: Full Function Generator (identical architecture) ---

    ch4Rise = (ch4_rise * (2 ** (ch4_rise_cv.clip(-1, 1) * 4))).clip(0.001, 25);
    ch4Fall = (ch4_fall * (2 ** (ch4_fall_cv.clip(-1, 1) * 4))).clip(0.001, 25);

    ch4ReTrig = Trig1.ar(ch4_trig + trig, 0.001);

    ch4Env = EnvGen.ar(
        Env(
            [0, 1, 0],
            [ch4Rise, ch4Fall],
            [ch4_curve.clip(-8, 8), ch4_curve.clip(-8, 8).neg]
        ),
        ch4ReTrig + (gate * Impulse.ar(0)),
        doneAction: 0
    );

    ch4Phase = Phasor.ar(
        ch4ReTrig,
        (1 / ((ch4Rise + ch4Fall) * SampleRate.ir)).clip(0, 1),
        0, 1
    );

    ch4Sig = {
        var risePortion = (ch4Rise / (ch4Rise + ch4Fall)).clip(0.001, 0.999);
        var risePhase = (ch4Phase / risePortion).clip(0, 1);
        var fallPhase = ((ch4Phase - risePortion) / (1 - risePortion)).clip(0, 1);
        var inRise = (ch4Phase < risePortion);

        var curveAmt = ch4_curve.clip(-8, 8);
        var shapedRise = Select.ar((curveAmt.abs > 0.01).asInteger, [
            risePhase,
            risePhase.lincurve(0, 1, 0, 1, curveAmt)
        ]);
        var shapedFall = Select.ar((curveAmt.abs > 0.01).asInteger, [
            1 - fallPhase,
            fallPhase.lincurve(0, 1, 1, 0, curveAmt.neg)
        ]);

        (shapedRise * inRise) + (shapedFall * (1 - inRise));
    }.value;

    ch4Sig = Select.ar(ch4_cycle.clip(0, 1), [ch4Env, ch4Sig]);
    ch4Sig = ch4Sig * ch4_level.clip(0, 1);

    ch4Eor = {
        var risePortion = (ch4Rise / (ch4Rise + ch4Fall)).clip(0.001, 0.999);
        Trig1.kr(A2K.kr(ch4Phase) > risePortion, 0.001);
    }.value;
    ch4Eoc = Trig1.kr(A2K.kr(ch4Phase) < 0.01, 0.001);

    Out.kr(ch4_eor_bus, ch4Eor);
    Out.kr(ch4_eoc_bus, ch4Eoc);

    // --- Channel 2: Attenuverter ---
    // Bipolar scaling: input * atten, where atten ranges -1 to +1
    ch2Sig = (ch2_input + externalIn) * ch2_atten.clip(-1, 1);

    // --- Channel 3: Attenuverter ---
    ch3Sig = (ch3_input + externalIn) * ch3_atten.clip(-1, 1);

    // --- Derived outputs ---
    // SUM: algebraic sum of channels 1 and 4 (used for complex envelopes)
    sumOut = ch1Sig + ch4Sig;

    // OR: maximum of channels 1 and 4 (analog OR behavior)
    orOut = max(ch1Sig, ch4Sig);

    // Output: [ch1, ch4, ch2, ch3, sum, or] as 6-channel bundle
    Out.ar(outBus, [ch1Sig, ch4Sig, ch2Sig, ch3Sig, sumOut, orOut]);
}).add;

// ==========================================
// 2. HERMETIC QUAD — PoliMATHS Clone
// ==========================================
// 4 independent rise/fall function generators with cascading architecture.
// EOC of each channel can trigger the next, enabling complex sequenced
// envelopes, burst generators, and polyrhythmic modulation.
SynthDef(\hermetic_quad, {
    |outBus=0, inBus=0, gate=1, trig=0,

     // Channel A
     chA_rise=0.1,          // 0.001..25
     chA_fall=0.3,          // 0.001..25
     chA_curve=0.0,         // -8..+8
     chA_cycle=0,           // 0=one-shot, 1=cycling
     chA_trig=0,
     chA_rise_cv=0.0,
     chA_fall_cv=0.0,
     chA_level=1.0,
     chA_cascade=0,         // 0=off, 1=EOC triggers next channel

     // Channel B
     chB_rise=0.1,
     chB_fall=0.3,
     chB_curve=0.0,
     chB_cycle=0,
     chB_trig=0,
     chB_rise_cv=0.0,
     chB_fall_cv=0.0,
     chB_level=1.0,
     chB_cascade=0,

     // Channel C
     chC_rise=0.1,
     chC_fall=0.3,
     chC_curve=0.0,
     chC_cycle=0,
     chC_trig=0,
     chC_rise_cv=0.0,
     chC_fall_cv=0.0,
     chC_level=1.0,
     chC_cascade=0,

     // Channel D
     chD_rise=0.1,
     chD_fall=0.3,
     chD_curve=0.0,
     chD_cycle=0,
     chD_trig=0,
     chD_rise_cv=0.0,
     chD_fall_cv=0.0,
     chD_level=1.0,
     chD_cascade=0,         // wraps: D EOC -> A if enabled

     // Trigger output buses (control rate)
     chA_eor_bus=0, chA_eoc_bus=0,
     chB_eor_bus=0, chB_eoc_bus=0,
     chC_eor_bus=0, chC_eoc_bus=0,
     chD_eor_bus=0, chD_eoc_bus=0|

    // Per-channel function generator implemented as a reusable closure
    var makeChannel = { |rise, fall, curve, cycle, trigIn, riseCV, fallCV, level, eorBus, eocBus|
        var modRise, modFall, reTrig, env, phase, sig;
        var risePortion, risePhase, fallPhase, inRise;
        var curveAmt, shapedRise, shapedFall;
        var eor, eoc;

        modRise = (rise * (2 ** (riseCV.clip(-1, 1) * 4))).clip(0.001, 25);
        modFall = (fall * (2 ** (fallCV.clip(-1, 1) * 4))).clip(0.001, 25);

        reTrig = Trig1.ar(trigIn, 0.001);

        // One-shot envelope
        env = EnvGen.ar(
            Env(
                [0, 1, 0],
                [modRise, modFall],
                [curve.clip(-8, 8), curve.clip(-8, 8).neg]
            ),
            reTrig + (gate * Impulse.ar(0)),
            doneAction: 0
        );

        // Cycling mode via phasor
        phase = Phasor.ar(
            reTrig,
            (1 / ((modRise + modFall) * SampleRate.ir)).clip(0, 1),
            0, 1
        );

        risePortion = (modRise / (modRise + modFall)).clip(0.001, 0.999);
        risePhase = (phase / risePortion).clip(0, 1);
        fallPhase = ((phase - risePortion) / (1 - risePortion)).clip(0, 1);
        inRise = (phase < risePortion);

        curveAmt = curve.clip(-8, 8);
        shapedRise = Select.ar((curveAmt.abs > 0.01).asInteger, [
            risePhase,
            risePhase.lincurve(0, 1, 0, 1, curveAmt)
        ]);
        shapedFall = Select.ar((curveAmt.abs > 0.01).asInteger, [
            1 - fallPhase,
            fallPhase.lincurve(0, 1, 1, 0, curveAmt.neg)
        ]);

        sig = (shapedRise * inRise) + (shapedFall * (1 - inRise));
        sig = Select.ar(cycle.clip(0, 1), [env, sig]);
        sig = sig * level.clip(0, 1);

        // Trigger outputs
        eor = Trig1.kr(A2K.kr(phase) > risePortion, 0.001);
        eoc = Trig1.kr(A2K.kr(phase) < 0.01, 0.001);

        Out.kr(eorBus, eor);
        Out.kr(eocBus, eoc);

        // Return [signal, eoc_trigger_for_cascade]
        [sig, eoc];
    };

    // Cascade chain: A -> B -> C -> D -> (A)
    // Each channel's EOC can optionally trigger the next channel.
    // Use LocalIn/LocalOut for the D->A feedback path.
    var cascadeFeedback = LocalIn.kr(1);

    var chAResult = makeChannel.value(
        chA_rise, chA_fall, chA_curve, chA_cycle,
        chA_trig + trig + (cascadeFeedback * chD_cascade),
        chA_rise_cv, chA_fall_cv, chA_level,
        chA_eor_bus, chA_eoc_bus
    );
    var chASig = chAResult[0];
    var chAEoc = chAResult[1];

    var chBResult = makeChannel.value(
        chB_rise, chB_fall, chB_curve, chB_cycle,
        chB_trig + (chAEoc * chA_cascade),
        chB_rise_cv, chB_fall_cv, chB_level,
        chB_eor_bus, chB_eoc_bus
    );
    var chBSig = chBResult[0];
    var chBEoc = chBResult[1];

    var chCResult = makeChannel.value(
        chC_rise, chC_fall, chC_curve, chC_cycle,
        chC_trig + (chBEoc * chB_cascade),
        chC_rise_cv, chC_fall_cv, chC_level,
        chC_eor_bus, chC_eoc_bus
    );
    var chCSig = chCResult[0];
    var chCEoc = chCResult[1];

    var chDResult = makeChannel.value(
        chD_rise, chD_fall, chD_curve, chD_cycle,
        chD_trig + (chCEoc * chC_cascade),
        chD_rise_cv, chD_fall_cv, chD_level,
        chD_eor_bus, chD_eoc_bus
    );
    var chDSig = chDResult[0];
    var chDEoc = chDResult[1];

    // Feed D's EOC back to A (circular cascade)
    LocalOut.kr(chDEoc);

    // Output: 4-channel bundle [A, B, C, D]
    Out.ar(outBus, [chASig, chBSig, chCSig, chDSig]);
}).add;

// ==========================================
// 3. HERMETIC MONO — Function Clone
// ==========================================
// Single-channel function generator: the essential building block.
// One rise/fall function with shape control, cycle mode, and
// end-of-rise / end-of-cycle trigger outputs.
SynthDef(\hermetic_mono, {
    |outBus=0, inBus=0, gate=1, trig=0,

     rise=0.1,              // 0.001..25 seconds
     fall=0.3,              // 0.001..25 seconds
     curve=0.0,             // -8..+8 (neg=log, 0=lin, pos=exp)
     cycle=0,               // 0=one-shot, 1=cycling
     level=1.0,             // 0..1 output level
     rise_cv=0.0,           // -1..+1 CV modulation of rise time
     fall_cv=0.0,           // -1..+1 CV modulation of fall time

     // Trigger output buses (control rate)
     eor_bus=0,
     eoc_bus=0|

    var modRise, modFall, reTrig, env, phase, sig;
    var risePortion, risePhase, fallPhase, inRise;
    var curveAmt, shapedRise, shapedFall;
    var eor, eoc;

    // CV-modulated times: exponential scaling (1V/oct-style)
    modRise = (rise * (2 ** (rise_cv.clip(-1, 1) * 4))).clip(0.001, 25);
    modFall = (fall * (2 ** (fall_cv.clip(-1, 1) * 4))).clip(0.001, 25);

    reTrig = Trig1.ar(trig, 0.001);

    // One-shot mode: standard two-segment envelope
    env = EnvGen.ar(
        Env(
            [0, 1, 0],
            [modRise, modFall],
            [curve.clip(-8, 8), curve.clip(-8, 8).neg]
        ),
        reTrig + (gate * Impulse.ar(0)),
        doneAction: 0
    );

    // Cycling mode: phasor-based continuous function
    phase = Phasor.ar(
        reTrig,
        (1 / ((modRise + modFall) * SampleRate.ir)).clip(0, 1),
        0, 1
    );

    // Partition phase into rise and fall segments
    risePortion = (modRise / (modRise + modFall)).clip(0.001, 0.999);
    risePhase = (phase / risePortion).clip(0, 1);
    fallPhase = ((phase - risePortion) / (1 - risePortion)).clip(0, 1);
    inRise = (phase < risePortion);

    // Apply curve shaping (0 = linear, positive = exponential, negative = logarithmic)
    curveAmt = curve.clip(-8, 8);
    shapedRise = Select.ar((curveAmt.abs > 0.01).asInteger, [
        risePhase,
        risePhase.lincurve(0, 1, 0, 1, curveAmt)
    ]);
    shapedFall = Select.ar((curveAmt.abs > 0.01).asInteger, [
        1 - fallPhase,
        fallPhase.lincurve(0, 1, 1, 0, curveAmt.neg)
    ]);

    sig = (shapedRise * inRise) + (shapedFall * (1 - inRise));

    // Mode select: one-shot vs cycling
    sig = Select.ar(cycle.clip(0, 1), [env, sig]);
    sig = sig * level.clip(0, 1);

    // End-of-rise: fires when phase crosses the rise/fall boundary
    eor = Trig1.kr(A2K.kr(phase) > risePortion, 0.001);

    // End-of-cycle: fires when phase wraps back to start
    eoc = Trig1.kr(A2K.kr(phase) < 0.01, 0.001);

    Out.kr(eor_bus, eor);
    Out.kr(eoc_bus, eoc);

    Out.ar(outBus, sig);
}).add;

// ==========================================
// 4. HERMETIC CONTOUR — Contour Clone
// ==========================================
// ASR (Attack-Sustain-Release) contour generator with voltage-controlled
// shape. The gate input determines the sustain phase: signal rises during
// attack, holds at peak while gate is high, then falls during release.
// Shape CV morphs all segments between logarithmic and exponential.
SynthDef(\hermetic_contour, {
    |outBus=0, inBus=0, gate=1, trig=0,

     attack=0.1,            // 0.001..25 seconds
     sustain_level=1.0,     // 0..1 sustain amplitude
     release=0.5,           // 0.001..25 seconds
     shape=0.0,             // -8..+8 voltage-controlled curve
     attack_cv=0.0,         // -1..+1 CV modulation of attack
     release_cv=0.0,        // -1..+1 CV modulation of release
     shape_cv=0.0,          // -1..+1 CV modulation of shape
     level=1.0,             // 0..1 output level

     // Trigger output buses (control rate)
     eor_bus=0,             // end-of-rise (attack complete)
     eoc_bus=0|             // end-of-cycle (release complete)

    var modAttack, modRelease, modShape;
    var env, sig;
    var eor, eoc;
    var gateStatus, releasePhase;

    // CV-modulated parameters
    modAttack = (attack * (2 ** (attack_cv.clip(-1, 1) * 4))).clip(0.001, 25);
    modRelease = (release * (2 ** (release_cv.clip(-1, 1) * 4))).clip(0.001, 25);
    modShape = (shape + (shape_cv.clip(-1, 1) * 4)).clip(-8, 8);

    // ASR envelope: attack -> sustain (hold while gate high) -> release
    env = EnvGen.ar(
        Env(
            [0, sustain_level.clip(0, 1), 0],
            [modAttack, modRelease],
            [modShape, modShape.neg],
            releaseNode: 1  // sustain at node 1 until gate off
        ),
        gate,
        doneAction: 0
    );

    sig = env * level.clip(0, 1);

    // EOR: detect when attack phase completes (signal reaches sustain level)
    // Use amplitude follower to detect the moment signal stabilizes at peak
    gateStatus = Lag.kr(gate, 0.001);
    eor = Trig1.kr(
        (A2K.kr(sig) > (sustain_level.clip(0, 1) * 0.95)) * gateStatus,
        0.01
    );

    // EOC: detect when release completes (signal falls near zero after gate off)
    releasePhase = (1 - gateStatus); // high when gate is off
    eoc = Trig1.kr(
        (A2K.kr(sig) < 0.01) * releasePhase,
        0.01
    );

    Out.kr(eor_bus, eor);
    Out.kr(eoc_bus, eoc);

    Out.ar(outBus, sig);
}).add;

// ==========================================
// BUS ALLOCATION FOR HERMETIC MODULES
// ==========================================
// Allocate control buses for trigger outputs so modules can
// cross-patch EOR/EOC signals via the Brahma Patch Bay.

// Hermetic Dual buses
~SC_BUS.put(\hermetic_dual_ch1_eor, Bus.control(s, 1));
~SC_BUS.put(\hermetic_dual_ch1_eoc, Bus.control(s, 1));
~SC_BUS.put(\hermetic_dual_ch4_eor, Bus.control(s, 1));
~SC_BUS.put(\hermetic_dual_ch4_eoc, Bus.control(s, 1));

// Hermetic Quad buses (4 channels x 2 triggers)
~SC_BUS.put(\hermetic_quad_chA_eor, Bus.control(s, 1));
~SC_BUS.put(\hermetic_quad_chA_eoc, Bus.control(s, 1));
~SC_BUS.put(\hermetic_quad_chB_eor, Bus.control(s, 1));
~SC_BUS.put(\hermetic_quad_chB_eoc, Bus.control(s, 1));
~SC_BUS.put(\hermetic_quad_chC_eor, Bus.control(s, 1));
~SC_BUS.put(\hermetic_quad_chC_eoc, Bus.control(s, 1));
~SC_BUS.put(\hermetic_quad_chD_eor, Bus.control(s, 1));
~SC_BUS.put(\hermetic_quad_chD_eoc, Bus.control(s, 1));

// Hermetic Mono buses
~SC_BUS.put(\hermetic_mono_eor, Bus.control(s, 1));
~SC_BUS.put(\hermetic_mono_eoc, Bus.control(s, 1));

// Hermetic Contour buses
~SC_BUS.put(\hermetic_contour_eor, Bus.control(s, 1));
~SC_BUS.put(\hermetic_contour_eoc, Bus.control(s, 1));

// Audio output buses
~SC_BUS.put(\hermetic_dual_out, Bus.audio(s, 6));   // ch1, ch4, ch2, ch3, sum, or
~SC_BUS.put(\hermetic_quad_out, Bus.audio(s, 4));   // chA, chB, chC, chD
~SC_BUS.put(\hermetic_mono_out, Bus.audio(s, 1));
~SC_BUS.put(\hermetic_contour_out, Bus.audio(s, 1));

// ==========================================
// ENTITY REGISTRATION
// ==========================================
[
    [\hermetic_dual, "Function Generator (Dual)", 4001],
    [\hermetic_quad, "Function Generator (Quad)", 4002],
    [\hermetic_mono, "Function Generator (Mono)", 4003],
    [\hermetic_contour, "Contour Generator (ASR)", 4004]
].do({ |spec|
    var synthDef = spec[0];
    var type = spec[1];
    var id = spec[2];

    ~BRAHMA_REGISTRY.registerEntity(id, type, (
        spectral_profile: (centroid: 0.0, flatness: 0.0, bandwidth: 0.0, rolloff: 0.0),
        temporal_topology: (attack: 0.1, decay: 0.3, sustain: 1.0, release: 0.5, slew: 0.5),
        modulation_graph: (type: synthDef, sources: 0, dests: 0, routes: 0),
        performance_response: (velocity: 0.0, aftertouch: 0.0, xy_sensitivity: 0.0, humanize: 0.0)
    ));
});

"--- BRAHMA: Hermetic Function Generators Online ---".postln;
"  HERMETIC DUAL (MATHS) | HERMETIC QUAD (PoliMATHS)".postln;
"  HERMETIC MONO (Function) | HERMETIC CONTOUR (Contour)".postln;

// ==========================================
// PATCH BAY REGISTRATION — Hermetic Function Generators
// ==========================================
// Register trigger outputs as sources (already have buses allocated)
[
    [\hermetic_dual_ch1_eor, "Hermetic Dual Ch1 End-of-Rise"],
    [\hermetic_dual_ch1_eoc, "Hermetic Dual Ch1 End-of-Cycle"],
    [\hermetic_dual_ch4_eor, "Hermetic Dual Ch4 End-of-Rise"],
    [\hermetic_dual_ch4_eoc, "Hermetic Dual Ch4 End-of-Cycle"],
    [\hermetic_quad_chA_eor, "Hermetic Quad ChA End-of-Rise"],
    [\hermetic_quad_chA_eoc, "Hermetic Quad ChA End-of-Cycle"],
    [\hermetic_quad_chB_eor, "Hermetic Quad ChB End-of-Rise"],
    [\hermetic_quad_chB_eoc, "Hermetic Quad ChB End-of-Cycle"],
    [\hermetic_quad_chC_eor, "Hermetic Quad ChC End-of-Rise"],
    [\hermetic_quad_chC_eoc, "Hermetic Quad ChC End-of-Cycle"],
    [\hermetic_quad_chD_eor, "Hermetic Quad ChD End-of-Rise"],
    [\hermetic_quad_chD_eoc, "Hermetic Quad ChD End-of-Cycle"],
    [\hermetic_mono_eor, "Hermetic Mono End-of-Rise"],
    [\hermetic_mono_eoc, "Hermetic Mono End-of-Cycle"],
    [\hermetic_contour_eor, "Hermetic Contour End-of-Rise"],
    [\hermetic_contour_eoc, "Hermetic Contour End-of-Cycle"]
].do({ |spec|
    var busName = spec[0];
    var desc = spec[1];
    ~PATCH_BAY.registerSource(busName, ~SC_BUS[busName], \control, desc);
});

// Register function generator parameters as destinations
[
    [\hermetic_dual, [
        [\ch1_rise, "Ch1 rise time"], [\ch1_fall, "Ch1 fall time"],
        [\ch1_curve, "Ch1 curve shape"], [\ch1_cycle, "Ch1 cycle mode"],
        [\ch4_rise, "Ch4 rise time"], [\ch4_fall, "Ch4 fall time"],
        [\ch4_curve, "Ch4 curve shape"], [\ch4_cycle, "Ch4 cycle mode"],
        [\ch2_atten, "Ch2 attenuverter"], [\ch3_atten, "Ch3 attenuverter"]
    ]],
    [\hermetic_mono, [
        [\rise, "Rise time"], [\fall, "Fall time"],
        [\curve, "Curve shape"], [\cycle, "Cycle mode"], [\level, "Level"]
    ]],
    [\hermetic_contour, [
        [\attack, "Attack time"], [\release, "Release time"],
        [\shape, "Curve shape"], [\sustain_level, "Sustain level"]
    ]]
].do({ |moduleSpec|
    var synthName = moduleSpec[0];
    var params = moduleSpec[1];
    params.do({ |paramSpec|
        ~PATCH_BAY.registerDestination(
            (synthName.asString ++ "_" ++ paramSpec[0].asString).asSymbol,
            paramSpec[0],
            synthName.asString ++ " " ++ paramSpec[1]
        );
    });
});

// ==========================================
// MODULE REGISTRY REGISTRATION — Hermetic Function Generators
// ==========================================
if(~MODULE_REGISTRY.notNil) {
    // 1. HERMETIC DUAL — MATHS Clone (dual function gen + attenuverters)
    ~MODULE_REGISTRY.register(\hermetic_dual, \makenoise, \hermetic_dual, [
        (\name: \ch1_rise, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "Ch1 rise time"),
        (\name: \ch1_fall, \default: 0.3, \min: 0.001, \max: 25, \units: "s", \desc: "Ch1 fall time"),
        (\name: \ch1_curve, \default: 0.0, \min: -8, \max: 8, \units: "", \desc: "Ch1 curve shape"),
        (\name: \ch1_cycle, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Ch1 cycle mode"),
        (\name: \ch1_rise_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Ch1 rise CV mod"),
        (\name: \ch1_fall_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Ch1 fall CV mod"),
        (\name: \ch1_level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "Ch1 output level"),
        (\name: \ch4_rise, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "Ch4 rise time"),
        (\name: \ch4_fall, \default: 0.3, \min: 0.001, \max: 25, \units: "s", \desc: "Ch4 fall time"),
        (\name: \ch4_curve, \default: 0.0, \min: -8, \max: 8, \units: "", \desc: "Ch4 curve shape"),
        (\name: \ch4_cycle, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Ch4 cycle mode"),
        (\name: \ch4_rise_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Ch4 rise CV mod"),
        (\name: \ch4_fall_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Ch4 fall CV mod"),
        (\name: \ch4_level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "Ch4 output level"),
        (\name: \ch2_atten, \default: 0.5, \min: -1, \max: 1, \units: "", \desc: "Ch2 attenuverter"),
        (\name: \ch3_atten, \default: 0.5, \min: -1, \max: 1, \units: "", \desc: "Ch3 attenuverter"),
    ], ~SC_GRP[\te], "MATHS clone: dual function gen + attenuverters, SUM/OR outputs");

    // 2. HERMETIC QUAD — PoliMATHS Clone (4-channel cascading function gen)
    ~MODULE_REGISTRY.register(\hermetic_quad, \makenoise, \hermetic_quad, [
        (\name: \chA_rise, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "ChA rise time"),
        (\name: \chA_fall, \default: 0.3, \min: 0.001, \max: 25, \units: "s", \desc: "ChA fall time"),
        (\name: \chA_curve, \default: 0.0, \min: -8, \max: 8, \units: "", \desc: "ChA curve shape"),
        (\name: \chA_cycle, \default: 0, \min: 0, \max: 1, \units: "", \desc: "ChA cycle mode"),
        (\name: \chA_rise_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "ChA rise CV mod"),
        (\name: \chA_fall_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "ChA fall CV mod"),
        (\name: \chA_level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "ChA output level"),
        (\name: \chA_cascade, \default: 0, \min: 0, \max: 1, \units: "", \desc: "ChA cascade enable"),
        (\name: \chB_rise, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "ChB rise time"),
        (\name: \chB_fall, \default: 0.3, \min: 0.001, \max: 25, \units: "s", \desc: "ChB fall time"),
        (\name: \chB_curve, \default: 0.0, \min: -8, \max: 8, \units: "", \desc: "ChB curve shape"),
        (\name: \chB_cycle, \default: 0, \min: 0, \max: 1, \units: "", \desc: "ChB cycle mode"),
        (\name: \chB_rise_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "ChB rise CV mod"),
        (\name: \chB_fall_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "ChB fall CV mod"),
        (\name: \chB_level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "ChB output level"),
        (\name: \chB_cascade, \default: 0, \min: 0, \max: 1, \units: "", \desc: "ChB cascade enable"),
        (\name: \chC_rise, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "ChC rise time"),
        (\name: \chC_fall, \default: 0.3, \min: 0.001, \max: 25, \units: "s", \desc: "ChC fall time"),
        (\name: \chC_curve, \default: 0.0, \min: -8, \max: 8, \units: "", \desc: "ChC curve shape"),
        (\name: \chC_cycle, \default: 0, \min: 0, \max: 1, \units: "", \desc: "ChC cycle mode"),
        (\name: \chC_rise_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "ChC rise CV mod"),
        (\name: \chC_fall_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "ChC fall CV mod"),
        (\name: \chC_level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "ChC output level"),
        (\name: \chC_cascade, \default: 0, \min: 0, \max: 1, \units: "", \desc: "ChC cascade enable"),
        (\name: \chD_rise, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "ChD rise time"),
        (\name: \chD_fall, \default: 0.3, \min: 0.001, \max: 25, \units: "s", \desc: "ChD fall time"),
        (\name: \chD_curve, \default: 0.0, \min: -8, \max: 8, \units: "", \desc: "ChD curve shape"),
        (\name: \chD_cycle, \default: 0, \min: 0, \max: 1, \units: "", \desc: "ChD cycle mode"),
        (\name: \chD_rise_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "ChD rise CV mod"),
        (\name: \chD_fall_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "ChD fall CV mod"),
        (\name: \chD_level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "ChD output level"),
        (\name: \chD_cascade, \default: 0, \min: 0, \max: 1, \units: "", \desc: "ChD cascade enable"),
    ], ~SC_GRP[\te], "PoliMATHS clone: 4-channel cascading function gen with circular trigger chain");

    // 3. HERMETIC MONO — Function Clone (single channel function gen)
    ~MODULE_REGISTRY.register(\hermetic_mono, \makenoise, \hermetic_mono, [
        (\name: \rise, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "Rise time"),
        (\name: \fall, \default: 0.3, \min: 0.001, \max: 25, \units: "s", \desc: "Fall time"),
        (\name: \curve, \default: 0.0, \min: -8, \max: 8, \units: "", \desc: "Curve shape"),
        (\name: \cycle, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Cycle mode"),
        (\name: \level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "Output level"),
        (\name: \rise_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Rise CV modulation"),
        (\name: \fall_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Fall CV modulation"),
    ], ~SC_GRP[\te], "Function clone: single-channel rise/fall function generator");

    // 4. HERMETIC CONTOUR — Contour Clone (ASR contour generator)
    ~MODULE_REGISTRY.register(\hermetic_contour, \makenoise, \hermetic_contour, [
        (\name: \attack, \default: 0.1, \min: 0.001, \max: 25, \units: "s", \desc: "Attack time"),
        (\name: \sustain_level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "Sustain level"),
        (\name: \release, \default: 0.5, \min: 0.001, \max: 25, \units: "s", \desc: "Release time"),
        (\name: \shape, \default: 0.0, \min: -8, \max: 8, \units: "", \desc: "Curve shape"),
        (\name: \attack_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Attack CV modulation"),
        (\name: \release_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Release CV modulation"),
        (\name: \shape_cv, \default: 0.0, \min: -1, \max: 1, \units: "", \desc: "Shape CV modulation"),
        (\name: \level, \default: 1.0, \min: 0, \max: 1, \units: "", \desc: "Output level"),
    ], ~SC_GRP[\te], "Contour clone: ASR contour generator with voltage-controlled shape");
};
)
