/*
  Phase 4: AION — Time-Based FX
  Delays, Reverbs, Freeze
*/

(
// ==========================================
// STEREO DELAY
// ==========================================
SynthDef(\aion_stereo_delay, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     timeL=0.25, timeR=0.375,
     feedbackL=0.3, feedbackR=0.3,
     crossFeedback=0,    // Cross-channel feedback
     pingPong=0,         // 0=independent, 1=ping-pong
     filterFreq=8000|    // LP in feedback path

    var input, fb, delL, delR, sig;

    input = In.ar(inBus, 1);
    fb = LocalIn.ar(2);

    // Filter in feedback path
    fb = LPF.ar(fb, filterFreq.clip(200, 18000));

    // Cross feedback
    fb = [
        fb[0] + (fb[1] * crossFeedback.clip(0, 0.5)),
        fb[1] + (fb[0] * crossFeedback.clip(0, 0.5))
    ];

    delL = DelayL.ar(input + (fb[0] * feedbackL.clip(0, 0.95)),
        4.0, timeL.clip(0.001, 4.0));
    delR = DelayL.ar(input + (fb[1] * feedbackR.clip(0, 0.95)),
        4.0, timeR.clip(0.001, 4.0));

    // Ping-pong: feed L into R and vice versa
    delL = Select.ar(pingPong.clip(0, 1), [delL, DelayL.ar(input + (fb[1] * feedbackL.clip(0, 0.95)), 4.0, timeL.clip(0.001, 4.0))]);
    delR = Select.ar(pingPong.clip(0, 1), [delR, DelayL.ar(delL + (fb[0] * feedbackR.clip(0, 0.95)), 4.0, timeR.clip(0.001, 4.0))]);

    LocalOut.ar([delL, delR]);

    sig = XFade2.ar(Pan2.ar(input), [delL, delR], mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// TAPE DELAY
// ==========================================
SynthDef(\aion_tape_delay, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     time=0.3, feedback=0.4,
     wow=0.1, flutter=0.3,        // Tape imperfections
     saturation=0.3,              // Tape saturation
     degradation=0,               // High-freq loss per repeat
     speed=1.0|                   // Variable speed (0.5-2)

    var input, fb, modTime, delayed, saturated, sig;

    input = In.ar(inBus, 1);
    fb = LocalIn.ar(1);

    // Wow & flutter modulation on delay time
    modTime = time * speed.clip(0.25, 4)
        + (SinOsc.kr(0.5) * wow.clip(0, 1) * 0.003)
        + (SinOsc.kr(6 + LFNoise1.kr(2)) * flutter.clip(0, 1) * 0.0005);

    // Degradation: LP filter in feedback (each repeat loses highs)
    fb = LPF.ar(fb, (18000 * (1 - degradation.clip(0, 0.9))).clip(500, 18000));

    // Tape saturation
    saturated = (fb * (1 + (saturation.clip(0, 1) * 4))).tanh;

    delayed = DelayL.ar(input + (saturated * feedback.clip(0, 0.95)),
        4.0, modTime.clip(0.001, 4.0));

    LocalOut.ar(delayed);

    sig = XFade2.ar(input, delayed, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// MULTI-TAP DELAY (8 taps)
// ==========================================
SynthDef(\aion_multitap, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     t1=0.1, t2=0.2, t3=0.3, t4=0.4, t5=0.5, t6=0.6, t7=0.7, t8=0.8,
     l1=1, l2=0.8, l3=0.6, l4=0.5, l5=0.4, l6=0.3, l7=0.2, l8=0.15,
     p1=0, p2=(-0.5), p3=0.5, p4=(-0.3), p5=0.3, p6=(-0.7), p7=0.7, p8=0,
     feedback=0.2, filterFreq=6000|

    var input, fb, taps, sig;

    input = In.ar(inBus, 1);
    fb = LocalIn.ar(1);
    fb = LPF.ar(fb, filterFreq.clip(200, 18000));

    taps = [
        Pan2.ar(DelayL.ar(input, 4, t1.clip(0.001, 4)) * l1, p1),
        Pan2.ar(DelayL.ar(input, 4, t2.clip(0.001, 4)) * l2, p2),
        Pan2.ar(DelayL.ar(input, 4, t3.clip(0.001, 4)) * l3, p3),
        Pan2.ar(DelayL.ar(input, 4, t4.clip(0.001, 4)) * l4, p4),
        Pan2.ar(DelayL.ar(input, 4, t5.clip(0.001, 4)) * l5, p5),
        Pan2.ar(DelayL.ar(input, 4, t6.clip(0.001, 4)) * l6, p6),
        Pan2.ar(DelayL.ar(input, 4, t7.clip(0.001, 4)) * l7, p7),
        Pan2.ar(DelayL.ar(input, 4, t8.clip(0.001, 4)) * l8, p8)
    ];

    LocalOut.ar(Mix.ar(taps).sum * feedback.clip(0, 0.5));

    sig = Mix.ar(taps);
    sig = XFade2.ar(Pan2.ar(input), sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// GRANULAR DELAY
// ==========================================
SynthDef(\aion_granular_delay, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     grainSize=0.1, density=10, pitch=1.0,
     posRand=0.1, feedback=0.3, time=0.5|

    var input, buf, delayed, grains, sig;

    input = In.ar(inBus, 1);

    // Write to circular buffer
    buf = LocalBuf(SampleRate.ir * 4, 1);
    RecordBuf.ar(input + (LocalIn.ar(1) * feedback.clip(0, 0.9)),
        buf, loop: 1);

    // Granular playback from buffer
    grains = GrainBuf.ar(
        2,
        Dust.ar(density.clip(1, 100)),
        grainSize.clip(0.01, 1),
        buf,
        pitch.clip(0.25, 4),
        (time.clip(0, 1) + (WhiteNoise.kr * posRand.clip(0, 0.5))).wrap(0, 1),
        pan: WhiteNoise.kr * 0.5
    );

    LocalOut.ar(Mix.ar(grains));

    sig = XFade2.ar(Pan2.ar(input), grains, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// REVERBS: Room, Hall, Plate, Spring, Shimmer
// ==========================================
SynthDef(\aion_room, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     decay=0.5, damping=0.5, size=0.5|

    var input, verb, sig;
    input = In.ar(inBus, 1);
    verb = FreeVerb.ar(input, 1, size.clip(0, 1), damping.clip(0, 1));

    sig = XFade2.ar(input, verb, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\aion_hall, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     decay=2.0, damping=0.3, size=0.8, preDelay=0.03|

    var input, pre, verb, sig;
    input = In.ar(inBus, 1);
    pre = DelayL.ar(input, 0.5, preDelay.clip(0, 0.5));

    // Dense allpass chain for hall
    verb = pre;
    4.do({ |i|
        verb = AllpassL.ar(verb, 0.1,
            [0.034, 0.047, 0.061, 0.079][i] * size.clip(0.1, 2),
            decay.clip(0.1, 20));
    });
    verb = LPF.ar(verb, (18000 * (1 - damping.clip(0, 0.9))).clip(500, 18000));

    sig = XFade2.ar(input, verb, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\aion_plate, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     decay=1.5, damping=0.3, brightness=0.7|

    var input, verb, sig;
    input = In.ar(inBus, 1);

    // Plate reverb: short, dense, bright
    verb = Mix.fill(8, { |i|
        AllpassL.ar(input, 0.05,
            rrand(0.005, 0.04),
            decay.clip(0.1, 10) * rrand(0.8, 1.2));
    }) / 4;

    verb = LPF.ar(verb, brightness.linexp(0, 1, 2000, 18000));
    verb = HPF.ar(verb, 100);

    sig = XFade2.ar(input, verb, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\aion_spring, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     decay=1.0, tension=0.5, drip=0.3|

    var input, spring, sig;
    input = In.ar(inBus, 1);

    // Spring reverb: comb filters with characteristic boing
    spring = Mix.fill(3, { |i|
        var dt = [0.023, 0.031, 0.019][i] * tension.linexp(0, 1, 0.5, 2);
        CombL.ar(input, 0.1, dt, decay.clip(0.1, 5)) * 0.3;
    });

    // Drip: add some metallic resonance
    spring = spring + (Ringz.ar(input * drip.clip(0, 1), 2000, 0.05) * 0.1);

    sig = XFade2.ar(input, spring, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\aion_shimmer, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     decay=3.0, damping=0.2, shimmerAmt=0.5|

    var input, verb, shifted, sig;
    input = In.ar(inBus, 1);

    // Base reverb
    verb = input + (LocalIn.ar(1) * decay.clip(0, 0.98).min(0.98));

    verb = Mix.fill(4, { |i|
        AllpassL.ar(verb, 0.1,
            [0.037, 0.053, 0.071, 0.089][i],
            decay.clip(0.1, 20));
    }) / 2;

    verb = LPF.ar(verb, (18000 * (1 - damping.clip(0, 0.9))).clip(500, 18000));

    // Octave-up pitch shift in feedback (shimmer)
    shifted = PitchShift.ar(verb, 0.2, 2.0, 0.01, 0.01) * shimmerAmt.clip(0, 1);

    LocalOut.ar((verb + shifted) * 0.5);

    sig = XFade2.ar(input, verb, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// FREEZE REVERB
// ==========================================
SynthDef(\aion_freeze, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     freeze=0, decay=5.0|

    var input, frozen, sig;
    input = In.ar(inBus, 1);

    // When freeze is on, feedback = 1.0 (infinite sustain)
    frozen = input + (LocalIn.ar(1) * Select.kr(freeze.clip(0, 1), [
        decay.clip(0, 0.98).min(0.98),
        1.0
    ]));

    frozen = Mix.fill(4, { |i|
        AllpassL.ar(frozen, 0.1, [0.041, 0.058, 0.073, 0.091][i], 5);
    }) / 2;

    // Gate input when frozen (only sustain existing content)
    frozen = Select.ar(freeze.clip(0, 1), [frozen, frozen * 0.999]);

    LocalOut.ar(frozen * 0.5);

    sig = XFade2.ar(input, frozen, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// CONVOLUTION REVERB
// ==========================================
// Uses a loaded impulse response buffer for true convolution.
// The IR buffer must be loaded separately before instantiation.
// Use PartConv for efficient partitioned convolution.
SynthDef(\aion_convolution, {
    |inBus=0, outBus=0, mix=0.3, bypass=0,
     irBufnum=0,         // Impulse response buffer (must be prepared with PartConv)
     irSize=2048,        // FFT size for partitioned convolution
     preDelay=0,         // Pre-delay in ms (0-200)
     damping=0.3,        // HF damping on wet signal
     level=1.0|          // Wet signal level

    var input, dry, pre_delayed, convolved, dampened, sig;

    input = In.ar(inBus, 1);
    dry = input;

    // Pre-delay
    pre_delayed = DelayL.ar(input, 0.2, (preDelay.clip(0, 200) / 1000));

    // Partitioned convolution (CPU-efficient for long IRs)
    convolved = PartConv.ar(pre_delayed, irSize.clip(256, 8192), irBufnum);

    // Damping: LP filter on wet signal
    dampened = LPF.ar(convolved, (18000 * (1 - damping.clip(0, 0.9))).clip(500, 18000));

    dampened = dampened * level.clip(0, 2);

    sig = XFade2.ar(dry, dampened, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, dry]);

    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: AION Time-Based FX Online (12 processors) ---".postln;

// ==========================================
// PATCH BAY REGISTRATION — Time-Based FX
// ==========================================
[
    [\aion_stereo_delay, [
        [\timeL, "Left delay time"], [\timeR, "Right delay time"],
        [\feedbackL, "Left feedback"], [\feedbackR, "Right feedback"],
        [\filterFreq, "Filter frequency"], [\mix, "Dry/wet mix"]
    ]],
    [\aion_tape_delay, [
        [\time, "Delay time"], [\feedback, "Feedback"],
        [\wow, "Wow amount"], [\flutter, "Flutter amount"],
        [\saturation, "Tape saturation"], [\speed, "Tape speed"],
        [\mix, "Dry/wet mix"]
    ]],
    [\aion_multitap, [
        [\feedback, "Tap feedback"], [\filterFreq, "Filter frequency"],
        [\mix, "Dry/wet mix"]
    ]],
    [\aion_granular_delay, [
        [\grainSize, "Grain size"], [\density, "Grain density"],
        [\pitch, "Grain pitch"], [\feedback, "Feedback"],
        [\time, "Delay time"], [\mix, "Dry/wet mix"]
    ]],
    [\aion_room, [
        [\decay, "Reverb decay"], [\damping, "HF damping"],
        [\size, "Room size"], [\mix, "Dry/wet mix"]
    ]],
    [\aion_hall, [
        [\decay, "Hall decay"], [\damping, "HF damping"],
        [\size, "Hall size"], [\preDelay, "Pre-delay"],
        [\mix, "Dry/wet mix"]
    ]],
    [\aion_plate, [
        [\decay, "Plate decay"], [\damping, "HF damping"],
        [\brightness, "Brightness"], [\mix, "Dry/wet mix"]
    ]],
    [\aion_spring, [
        [\decay, "Spring decay"], [\tension, "Spring tension"],
        [\drip, "Drip amount"], [\mix, "Dry/wet mix"]
    ]],
    [\aion_shimmer, [
        [\decay, "Shimmer decay"], [\damping, "HF damping"],
        [\shimmerAmt, "Shimmer amount"], [\mix, "Dry/wet mix"]
    ]],
    [\aion_freeze, [
        [\freeze, "Freeze toggle"], [\decay, "Decay time"],
        [\mix, "Dry/wet mix"]
    ]],
    [\aion_convolution, [
        [\preDelay, "Pre-delay ms"], [\damping, "HF damping"],
        [\level, "Wet level"], [\mix, "Dry/wet mix"]
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
    ~MODULE_REGISTRY.register(\aion_stereo_delay, \fx, \aion_stereo_delay, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \timeL, \default: 0.25, \min: 0.001, \max: 4.0, \units: "s", \desc: "Left delay time"),
        (\name: \timeR, \default: 0.375, \min: 0.001, \max: 4.0, \units: "s", \desc: "Right delay time"),
        (\name: \feedbackL, \default: 0.3, \min: 0, \max: 0.95, \units: "", \desc: "Left feedback"),
        (\name: \feedbackR, \default: 0.3, \min: 0, \max: 0.95, \units: "", \desc: "Right feedback"),
        (\name: \crossFeedback, \default: 0, \min: 0, \max: 0.5, \units: "", \desc: "Cross-channel feedback"),
        (\name: \pingPong, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Ping-pong mode (0=independent, 1=ping-pong)"),
        (\name: \filterFreq, \default: 8000, \min: 200, \max: 18000, \units: "Hz", \desc: "Feedback LP filter frequency"),
    ], ~SC_GRP[\rr], "Stereo delay with ping-pong and cross-feedback");

    ~MODULE_REGISTRY.register(\aion_tape_delay, \fx, \aion_tape_delay, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \time, \default: 0.3, \min: 0.001, \max: 4.0, \units: "s", \desc: "Delay time"),
        (\name: \feedback, \default: 0.4, \min: 0, \max: 0.95, \units: "", \desc: "Feedback amount"),
        (\name: \wow, \default: 0.1, \min: 0, \max: 1, \units: "", \desc: "Wow modulation (slow pitch drift)"),
        (\name: \flutter, \default: 0.3, \min: 0, \max: 1, \units: "", \desc: "Flutter modulation (fast pitch jitter)"),
        (\name: \saturation, \default: 0.3, \min: 0, \max: 1, \units: "", \desc: "Tape saturation"),
        (\name: \degradation, \default: 0, \min: 0, \max: 0.9, \units: "", \desc: "HF loss per repeat"),
        (\name: \speed, \default: 1.0, \min: 0.25, \max: 4, \units: "x", \desc: "Variable tape speed"),
    ], ~SC_GRP[\rr], "Tape delay with wow, flutter, and saturation");

    ~MODULE_REGISTRY.register(\aion_multitap, \fx, \aion_multitap, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \t1, \default: 0.1, \min: 0.001, \max: 4, \units: "s", \desc: "Tap 1 time"),
        (\name: \t2, \default: 0.2, \min: 0.001, \max: 4, \units: "s", \desc: "Tap 2 time"),
        (\name: \t3, \default: 0.3, \min: 0.001, \max: 4, \units: "s", \desc: "Tap 3 time"),
        (\name: \t4, \default: 0.4, \min: 0.001, \max: 4, \units: "s", \desc: "Tap 4 time"),
        (\name: \t5, \default: 0.5, \min: 0.001, \max: 4, \units: "s", \desc: "Tap 5 time"),
        (\name: \t6, \default: 0.6, \min: 0.001, \max: 4, \units: "s", \desc: "Tap 6 time"),
        (\name: \t7, \default: 0.7, \min: 0.001, \max: 4, \units: "s", \desc: "Tap 7 time"),
        (\name: \t8, \default: 0.8, \min: 0.001, \max: 4, \units: "s", \desc: "Tap 8 time"),
        (\name: \l1, \default: 1, \min: 0, \max: 1, \units: "", \desc: "Tap 1 level"),
        (\name: \l2, \default: 0.8, \min: 0, \max: 1, \units: "", \desc: "Tap 2 level"),
        (\name: \l3, \default: 0.6, \min: 0, \max: 1, \units: "", \desc: "Tap 3 level"),
        (\name: \l4, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Tap 4 level"),
        (\name: \l5, \default: 0.4, \min: 0, \max: 1, \units: "", \desc: "Tap 5 level"),
        (\name: \l6, \default: 0.3, \min: 0, \max: 1, \units: "", \desc: "Tap 6 level"),
        (\name: \l7, \default: 0.2, \min: 0, \max: 1, \units: "", \desc: "Tap 7 level"),
        (\name: \l8, \default: 0.15, \min: 0, \max: 1, \units: "", \desc: "Tap 8 level"),
        (\name: \p1, \default: 0, \min: -1, \max: 1, \units: "", \desc: "Tap 1 pan"),
        (\name: \p2, \default: -0.5, \min: -1, \max: 1, \units: "", \desc: "Tap 2 pan"),
        (\name: \p3, \default: 0.5, \min: -1, \max: 1, \units: "", \desc: "Tap 3 pan"),
        (\name: \p4, \default: -0.3, \min: -1, \max: 1, \units: "", \desc: "Tap 4 pan"),
        (\name: \p5, \default: 0.3, \min: -1, \max: 1, \units: "", \desc: "Tap 5 pan"),
        (\name: \p6, \default: -0.7, \min: -1, \max: 1, \units: "", \desc: "Tap 6 pan"),
        (\name: \p7, \default: 0.7, \min: -1, \max: 1, \units: "", \desc: "Tap 7 pan"),
        (\name: \p8, \default: 0, \min: -1, \max: 1, \units: "", \desc: "Tap 8 pan"),
        (\name: \feedback, \default: 0.2, \min: 0, \max: 0.5, \units: "", \desc: "Tap feedback"),
        (\name: \filterFreq, \default: 6000, \min: 200, \max: 18000, \units: "Hz", \desc: "Feedback LP filter"),
    ], ~SC_GRP[\rr], "8-tap stereo delay with per-tap time, level, and pan");

    ~MODULE_REGISTRY.register(\aion_granular_delay, \fx, \aion_granular_delay, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \grainSize, \default: 0.1, \min: 0.01, \max: 1, \units: "s", \desc: "Grain duration"),
        (\name: \density, \default: 10, \min: 1, \max: 100, \units: "Hz", \desc: "Grain trigger density"),
        (\name: \pitch, \default: 1.0, \min: 0.25, \max: 4, \units: "x", \desc: "Grain playback pitch"),
        (\name: \posRand, \default: 0.1, \min: 0, \max: 0.5, \units: "", \desc: "Position randomization"),
        (\name: \feedback, \default: 0.3, \min: 0, \max: 0.9, \units: "", \desc: "Feedback amount"),
        (\name: \time, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Playback position in buffer"),
    ], ~SC_GRP[\rr], "Granular delay with pitch and density control");

    ~MODULE_REGISTRY.register(\aion_room, \fx, \aion_room, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \decay, \default: 0.5, \min: 0.1, \max: 10, \units: "s", \desc: "Reverb decay time"),
        (\name: \damping, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "HF damping"),
        (\name: \size, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Room size"),
    ], ~SC_GRP[\rr], "Room reverb (FreeVerb)");

    ~MODULE_REGISTRY.register(\aion_hall, \fx, \aion_hall, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \decay, \default: 2.0, \min: 0.1, \max: 20, \units: "s", \desc: "Hall decay time"),
        (\name: \damping, \default: 0.3, \min: 0, \max: 0.9, \units: "", \desc: "HF damping"),
        (\name: \size, \default: 0.8, \min: 0.1, \max: 2, \units: "", \desc: "Hall size"),
        (\name: \preDelay, \default: 0.03, \min: 0, \max: 0.5, \units: "s", \desc: "Pre-delay time"),
    ], ~SC_GRP[\rr], "Hall reverb with allpass diffusion");

    ~MODULE_REGISTRY.register(\aion_plate, \fx, \aion_plate, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \decay, \default: 1.5, \min: 0.1, \max: 10, \units: "s", \desc: "Plate decay time"),
        (\name: \damping, \default: 0.3, \min: 0, \max: 1, \units: "", \desc: "HF damping"),
        (\name: \brightness, \default: 0.7, \min: 0, \max: 1, \units: "", \desc: "Brightness (HF content)"),
    ], ~SC_GRP[\rr], "Plate reverb (dense, bright)");

    ~MODULE_REGISTRY.register(\aion_spring, \fx, \aion_spring, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \decay, \default: 1.0, \min: 0.1, \max: 5, \units: "s", \desc: "Spring decay time"),
        (\name: \tension, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Spring tension"),
        (\name: \drip, \default: 0.3, \min: 0, \max: 1, \units: "", \desc: "Metallic drip amount"),
    ], ~SC_GRP[\rr], "Spring reverb with tension and drip");

    ~MODULE_REGISTRY.register(\aion_shimmer, \fx, \aion_shimmer, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \decay, \default: 3.0, \min: 0.1, \max: 20, \units: "s", \desc: "Shimmer decay time"),
        (\name: \damping, \default: 0.2, \min: 0, \max: 0.9, \units: "", \desc: "HF damping"),
        (\name: \shimmerAmt, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Shimmer (octave-up) amount"),
    ], ~SC_GRP[\rr], "Shimmer reverb with octave-up feedback");

    ~MODULE_REGISTRY.register(\aion_freeze, \fx, \aion_freeze, [
        (\name: \mix, \default: 0.5, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \freeze, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Freeze toggle (infinite sustain)"),
        (\name: \decay, \default: 5.0, \min: 0, \max: 0.98, \units: "", \desc: "Decay feedback (when not frozen)"),
    ], ~SC_GRP[\rr], "Freeze reverb with infinite sustain mode");

    ~MODULE_REGISTRY.register(\aion_convolution, \fx, \aion_convolution, [
        (\name: \mix, \default: 0.3, \min: 0, \max: 1, \units: "wet", \desc: "Dry/wet mix"),
        (\name: \bypass, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Bypass toggle"),
        (\name: \irBufnum, \default: 0, \min: 0, \max: 4096, \units: "", \desc: "IR buffer number"),
        (\name: \irSize, \default: 2048, \min: 256, \max: 8192, \units: "", \desc: "FFT partition size"),
        (\name: \preDelay, \default: 0, \min: 0, \max: 200, \units: "ms", \desc: "Pre-delay time"),
        (\name: \damping, \default: 0.3, \min: 0, \max: 0.9, \units: "", \desc: "HF damping on wet signal"),
        (\name: \level, \default: 1.0, \min: 0, \max: 2, \units: "", \desc: "Wet signal level"),
    ], ~SC_GRP[\rr], "Partitioned convolution reverb");

    "  -> 12 Time-Based FX registered with Module Registry".postln;
};
)
