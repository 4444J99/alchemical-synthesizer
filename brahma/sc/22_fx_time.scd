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

"--- BRAHMA: AION Time-Based FX Online (11 processors) ---".postln;
)
