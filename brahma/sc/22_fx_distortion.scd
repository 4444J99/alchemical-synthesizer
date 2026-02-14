/*
  Phase 4: CALCINATION — Distortion FX
  Overdrive, Fuzz, Waveshaper, Tube Saturation,
  Decimation, Clipper
*/

(
SynthDef(\calcination_overdrive, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     gain=0.5, tone=0.5, asymmetry=0|

    var input, driven, toned, sig;
    input = In.ar(inBus, 1);

    driven = (input * (1 + (gain.clip(0, 1) * 19))).tanh;

    // Asymmetry: clip positive side more than negative
    if(asymmetry > 0, {
        driven = driven.clip(asymmetry.clip(0, 0.5).neg, 1);
    });

    toned = LPF.ar(driven, tone.linexp(0, 1, 500, 15000));

    sig = XFade2.ar(input, toned, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, LeakDC.ar(sig));
}).add;

SynthDef(\calcination_fuzz, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     gain=0.7, gateThreshold=0.01, octaveUp=0|

    var input, rectified, fuzzed, gated, sig;
    input = In.ar(inBus, 1);

    // Optional octave-up (full-wave rectify before fuzz)
    rectified = Select.ar(octaveUp.clip(0, 1), [input, input.abs]);

    // Hard-clipping fuzz
    fuzzed = (rectified * (1 + (gain.clip(0, 1) * 49))).clip(-1, 1);

    // Gate to clean up noise floor
    gated = fuzzed * (Amplitude.kr(input, 0.001, 0.01) > gateThreshold.clip(0, 0.1));

    sig = XFade2.ar(input, gated, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\calcination_waveshaper, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     transferFunc=0, drive=0.5|
     // 0=tanh, 1=sine fold, 2=chebyshev, 3=custom sigmoid

    var input, shaped, sig;
    input = In.ar(inBus, 1);

    shaped = Select.ar(transferFunc.clip(0, 3), [
        // tanh
        (input * (1 + (drive.clip(0, 1) * 9))).tanh,
        // Sine fold
        (input * (1 + (drive.clip(0, 1) * 8))).sin,
        // Chebyshev polynomial (3rd order)
        { var x = input * (1 + (drive.clip(0, 1) * 3));
          (4 * x.cubed) - (3 * x); }.value,
        // Custom sigmoid
        (2 / (1 + (((input * (1 + (drive.clip(0, 1) * 9))).neg).exp))) - 1
    ]);

    sig = XFade2.ar(input, shaped, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, LeakDC.ar(sig));
}).add;

SynthDef(\calcination_tube, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     drive=0.5, bias=0.1, sag=0.1|

    var input, biased, tube, sagged, sig;
    input = In.ar(inBus, 1);

    // Bias: DC offset for asymmetric distortion (tube character)
    biased = input + (bias.clip(-0.5, 0.5) * 0.1);

    // Tube saturation: soft clip with asymmetric response
    tube = (biased * (1 + (drive.clip(0, 1) * 9))).softclip;

    // Sag: high-frequency loss under heavy drive (power supply sag simulation)
    sagged = LPF.ar(tube, (18000 * (1 - (sag.clip(0, 1) * drive.clip(0, 1) * 0.7))).clip(1000, 18000));

    sig = XFade2.ar(input, sagged, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, LeakDC.ar(sig));
}).add;

SynthDef(\calcination_decimator, {
    |inBus=0, outBus=0, mix=0.5, bypass=0,
     sampleRate=0.5, bitDepth=0.5|
     // 0..1 mapped to ranges

    var input, sr, bits, decimated, sig;
    input = In.ar(inBus, 1);

    sr = sampleRate.clip(0, 1).linexp(0, 1, 44100, 500);
    bits = bitDepth.clip(0, 1).linlin(0, 1, 24, 2);

    decimated = Latch.ar(input, Impulse.ar(sr));
    decimated = decimated.round(2.pow(bits.neg));

    sig = XFade2.ar(input, decimated, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

SynthDef(\calcination_clipper, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     clipType=0,      // 0=hard, 1=soft
     threshold=0.8, ceiling=1.0|

    var input, clipped, sig;
    input = In.ar(inBus, 1);

    clipped = Select.ar(clipType.clip(0, 1), [
        input.clip(threshold.clip(0.01, 1).neg, threshold.clip(0.01, 1)),
        input.softclip * threshold.clip(0.01, 1)
    ]);

    clipped = clipped * (ceiling.clip(0.1, 2) / threshold.clip(0.01, 1).max(0.01));

    sig = XFade2.ar(input, clipped, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);
    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: CALCINATION Distortion FX Online (6 processors) ---".postln;
)
