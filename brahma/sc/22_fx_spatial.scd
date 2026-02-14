/*
  Phase 4: AETHER — Spatial FX
  Stereo Width, Auto-Pan, Haas Effect, Mid/Side, Binaural Panner
*/

(
SynthDef(\aether_width, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     width=1.0|  // 0=mono, 1=normal, 2=super wide

    var input, mid, side, sig;
    input = In.ar(inBus, 2);

    // Mid/Side processing
    mid = (input[0] + input[1]) * 0.5;
    side = (input[0] - input[1]) * 0.5;

    // Width: scale side signal
    side = side * width.clip(0, 3);

    sig = [mid + side, mid - side];
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\aether_auto_pan, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     rate=1, depth=0.8, shape=0, syncToClockBus=0|

    var input, lfo, panned, sig;
    input = In.ar(inBus, 1);

    lfo = Select.kr(shape.clip(0, 2).round, [
        SinOsc.kr(rate.clip(0.01, 20)),
        LFTri.kr(rate.clip(0.01, 20)),
        LFSaw.kr(rate.clip(0.01, 20))
    ]);

    panned = Pan2.ar(input, lfo * depth.clip(0, 1));

    sig = XFade2.ar(Pan2.ar(input), panned, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\aether_haas, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     delayMs=15, side=0|  // 0=delay right, 1=delay left

    var input, delayed, sig;
    input = In.ar(inBus, 1);

    delayed = DelayL.ar(input, 0.04, delayMs.clip(1, 40) / 1000);

    sig = Select.ar(side.clip(0, 1), [
        [input, delayed],   // Delay right channel
        [delayed, input]    // Delay left channel
    ]);

    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);
    ReplaceOut.ar(outBus, sig);
}).add;

// Mid/Side encoder/decoder
SynthDef(\aether_ms_encode, {
    |inBus=0, outBusMid=0, outBusSide=1|

    var input, mid, side;
    input = In.ar(inBus, 2);

    mid = (input[0] + input[1]) * 0.5;
    side = (input[0] - input[1]) * 0.5;

    Out.ar(outBusMid, mid);
    Out.ar(outBusSide, side);
}).add;

SynthDef(\aether_ms_decode, {
    |inBusMid=0, inBusSide=1, outBus=0|

    var mid, side;
    mid = In.ar(inBusMid, 1);
    side = In.ar(inBusSide, 1);

    Out.ar(outBus, [mid + side, mid - side]);
}).add;

// Binaural panner (simplified HRTF approximation)
SynthDef(\aether_binaural, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     azimuth=0, elevation=0, distance=1|
     // azimuth: -1 to 1 (left to right)
     // elevation: -1 to 1 (below to above)

    var input, itdL, itdR, ildL, ildR, filteredL, filteredR, sig;
    input = In.ar(inBus, 1);

    // Interaural Time Difference (max ~0.7ms)
    itdL = ((1 - azimuth.clip(-1, 1)) * 0.00035).clip(0, 0.001);
    itdR = ((1 + azimuth.clip(-1, 1)) * 0.00035).clip(0, 0.001);

    // Interaural Level Difference
    ildL = (1 - (azimuth.clip(0, 1) * 0.5)) * (1 / distance.clip(0.1, 10));
    ildR = (1 + (azimuth.clip(-1, 0) * 0.5).abs) * (1 / distance.clip(0.1, 10));

    // Simplified head-shadow filtering (HF attenuation for far ear)
    filteredL = LPF.ar(
        DelayL.ar(input, 0.001, itdL),
        (8000 + (azimuth.clip(-1, 0) * 4000)).clip(2000, 18000)
    ) * ildL;

    filteredR = LPF.ar(
        DelayL.ar(input, 0.001, itdR),
        (8000 - (azimuth.clip(0, 1) * 4000)).clip(2000, 18000)
    ) * ildR;

    sig = [filteredL, filteredR];
    sig = Select.ar(bypass.clip(0, 1), [sig, Pan2.ar(input)]);
    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: AETHER Spatial FX Online (6 processors) ---".postln;
)
