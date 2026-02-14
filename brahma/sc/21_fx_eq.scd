/*
  Phase 4: PHILOSOPHERS_PRISM — EQ FX
  4-band Parametric, 8-band Graphic, Shelf, Tilt, Dynamic EQ
*/

(
// ==========================================
// 4-BAND PARAMETRIC EQ
// ==========================================
SynthDef(\prism_parametric, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     // Band 1 (low shelf or peak)
     b1Freq=100, b1Gain=0, b1Q=1, b1Type=0,
     // Band 2
     b2Freq=500, b2Gain=0, b2Q=1, b2Type=1,
     // Band 3
     b3Freq=2000, b3Gain=0, b3Q=1, b3Type=1,
     // Band 4 (high shelf or peak)
     b4Freq=8000, b4Gain=0, b4Q=1, b4Type=0|

    var input, sig;

    input = In.ar(inBus, 1);

    // Band 1
    sig = Select.ar(b1Type.clip(0, 1), [
        BLowShelf.ar(input, b1Freq.clip(20, 2000), 1, b1Gain.clip(-24, 24)),
        BPeakEQ.ar(input, b1Freq.clip(20, 20000), b1Q.clip(0.1, 20).reciprocal, b1Gain.clip(-24, 24))
    ]);

    // Band 2
    sig = BPeakEQ.ar(sig, b2Freq.clip(20, 20000), b2Q.clip(0.1, 20).reciprocal, b2Gain.clip(-24, 24));

    // Band 3
    sig = BPeakEQ.ar(sig, b3Freq.clip(20, 20000), b3Q.clip(0.1, 20).reciprocal, b3Gain.clip(-24, 24));

    // Band 4
    sig = Select.ar(b4Type.clip(0, 1), [
        BHiShelf.ar(sig, b4Freq.clip(500, 20000), 1, b4Gain.clip(-24, 24)),
        BPeakEQ.ar(sig, b4Freq.clip(20, 20000), b4Q.clip(0.1, 20).reciprocal, b4Gain.clip(-24, 24))
    ]);

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// 8-BAND GRAPHIC EQ
// ==========================================
SynthDef(\prism_graphic, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     g63=0, g125=0, g250=0, g500=0,
     g1k=0, g2k=0, g4k=0, g8k=0|

    var input, sig;

    input = In.ar(inBus, 1);

    sig = BPeakEQ.ar(input, 63, 1.4.reciprocal, g63.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 125, 1.4.reciprocal, g125.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 250, 1.4.reciprocal, g250.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 500, 1.4.reciprocal, g500.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 1000, 1.4.reciprocal, g1k.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 2000, 1.4.reciprocal, g2k.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 4000, 1.4.reciprocal, g4k.clip(-12, 12));
    sig = BPeakEQ.ar(sig, 8000, 1.4.reciprocal, g8k.clip(-12, 12));

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// HIGH/LOW SHELF
// ==========================================
SynthDef(\prism_shelf, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     lowFreq=200, lowGain=0, highFreq=4000, highGain=0|

    var input, sig;

    input = In.ar(inBus, 1);
    sig = BLowShelf.ar(input, lowFreq.clip(20, 2000), 1, lowGain.clip(-24, 24));
    sig = BHiShelf.ar(sig, highFreq.clip(500, 20000), 1, highGain.clip(-24, 24));

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// TILT EQ (Single Knob Tone Control)
// ==========================================
SynthDef(\prism_tilt, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     tilt=0, centerFreq=1000|  // -1 = dark, 0 = flat, +1 = bright

    var input, sig, tiltDb;

    input = In.ar(inBus, 1);
    tiltDb = tilt.clip(-1, 1) * 6;

    sig = BLowShelf.ar(input, centerFreq.clip(100, 5000), 1, tiltDb.neg);
    sig = BHiShelf.ar(sig, centerFreq.clip(100, 5000), 1, tiltDb);

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// DYNAMIC EQ (Frequency-Dependent Compression)
// ==========================================
SynthDef(\prism_dynamic, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     freq=2000, q=2, threshold=(-12), ratio=3,
     attack=0.005, release=0.05|

    var input, band, env, gain, sig;

    input = In.ar(inBus, 1);

    // Extract band
    band = BPF.ar(input, freq.clip(20, 20000), q.clip(0.1, 20).reciprocal);

    // Compress just that band
    env = Amplitude.kr(band, attack, release);
    gain = Select.kr((env.ampdb > threshold).asInteger, [
        1,
        (threshold.dbamp / env).pow(1 - (1 / ratio.clip(1, 20)))
    ]);

    // Apply gain reduction to the band, recombine
    sig = input - band + (band * gain);

    sig = XFade2.ar(input, sig, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: PHILOSOPHERS_PRISM EQ FX Online (5 processors) ---".postln;
)
