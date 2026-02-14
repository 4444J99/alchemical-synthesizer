/*
  Phase 3: Make Noise Oscillator Clones
  DPO, STO, XPO, MultiWAVE, Spectraphon, tELHARMONIC
*/

(
// ==========================================
// PRISMATIC_TWIN — DPO (Dual Prismatic Oscillator)
// ==========================================
// Dual oscillator with FM/AM/wavefold, strike input, follow mode
SynthDef(\prismatic_twin, {
    |outBus=0, inBus=0, gate=1,
     // Oscillator A
     freqA=220, waveA=0, shapeA=0.5,
     // Oscillator B
     freqB=220, waveB=1, shapeB=0.5,
     // Modulation
     fmAtoB=0, fmBtoA=0,
     amAtoB=0,
     // Wavefold
     foldA=0, foldB=0,
     // Strike (one-shot excitation)
     strike=0,
     // Follow mode (B tracks A frequency)
     follow=0, followRatio=1.0,
     // Mix
     mixA=0.5, mixB=0.5|

    var oscA, oscB, strikeEnv, sig;
    var effFreqB;

    strikeEnv = EnvGen.ar(Env.perc(0.001, 0.3), strike);

    // Follow mode: B tracks A's frequency
    effFreqB = Select.kr(follow.clip(0, 1), [freqB, freqA * followRatio]);

    // Oscillator A (with FM from B)
    oscA = Select.ar(waveA.clip(0, 3), [
        SinOsc.ar(freqA + (SinOsc.ar(effFreqB) * freqA * fmBtoA)),
        LFTri.ar(freqA + (SinOsc.ar(effFreqB) * freqA * fmBtoA)),
        Saw.ar(freqA + (SinOsc.ar(effFreqB) * freqA * fmBtoA)),
        Pulse.ar(freqA + (SinOsc.ar(effFreqB) * freqA * fmBtoA), shapeA)
    ]);

    // Wavefold A
    oscA = Select.ar((foldA > 0.01).asInteger, [
        oscA,
        (oscA * (1 + (foldA.clip(0, 1) * 8))).sin
    ]);

    // Oscillator B (with FM from A, AM from A)
    oscB = Select.ar(waveB.clip(0, 3), [
        SinOsc.ar(effFreqB + (oscA * effFreqB * fmAtoB)),
        LFTri.ar(effFreqB + (oscA * effFreqB * fmAtoB)),
        Saw.ar(effFreqB + (oscA * effFreqB * fmAtoB)),
        Pulse.ar(effFreqB + (oscA * effFreqB * fmAtoB), shapeB)
    ]);

    // AM: A modulates B amplitude
    oscB = oscB * (1 + (oscA * amAtoB.clip(0, 1)));

    // Wavefold B
    oscB = Select.ar((foldB > 0.01).asInteger, [
        oscB,
        (oscB * (1 + (foldB.clip(0, 1) * 8))).sin
    ]);

    // Strike adds excitation impulse
    oscA = oscA + (strikeEnv * WhiteNoise.ar * 0.3);
    oscB = oscB + (strikeEnv * WhiteNoise.ar * 0.3);

    sig = (oscA * mixA.clip(0, 1)) + (oscB * mixB.clip(0, 1));

    Out.ar(outBus, LeakDC.ar(sig));
}).add;

// ==========================================
// PRISMATIC_MONO — STO (Sub Timbral Oscillator)
// ==========================================
SynthDef(\prismatic_mono, {
    |outBus=0, subOutBus=0, freq=220, shape=0.5|

    var osc, sub;

    // Continuously variable waveshape: sine → tri → saw
    osc = SelectX.ar(shape.clip(0, 1) * 2, [
        SinOsc.ar(freq),
        LFTri.ar(freq),
        Saw.ar(freq)
    ]);

    // Sub output (-1 octave square)
    sub = Pulse.ar(freq / 2, 0.5);

    Out.ar(outBus, osc);
    Out.ar(subOutBus, sub);
}).add;

// ==========================================
// PRISMATIC_STEREO — XPO (Stereo Prismatic Oscillator)
// ==========================================
SynthDef(\prismatic_stereo, {
    |outBus=0, freq=220, behavior=0,
     fmAmt=0, amAmt=0, foldAmt=0,
     shapeL=0, shapeR=0.5, spread=0.1|

    var oscL, oscR, sig;

    // Left oscillator
    oscL = Select.ar(shapeL.clip(0, 3).round, [
        SinOsc.ar(freq - spread),
        LFTri.ar(freq - spread),
        Saw.ar(freq - spread),
        Pulse.ar(freq - spread, 0.5)
    ]);

    // Right oscillator
    oscR = Select.ar(shapeR.clip(0, 3).round, [
        SinOsc.ar(freq + spread),
        LFTri.ar(freq + spread),
        Saw.ar(freq + spread),
        Pulse.ar(freq + spread, 0.5)
    ]);

    // Behavior modes: 0=independent, 1=FM, 2=AM, 3=fold, 4=sync, 5=ring
    sig = Select.ar(behavior.clip(0, 5).round, [
        [oscL, oscR],                                           // 0: Independent
        [SinOsc.ar(freq - spread + (oscR * freq * fmAmt)), oscR], // 1: FM
        [oscL * (1 + (oscR * amAmt)), oscR],                   // 2: AM
        [(oscL * (1 + foldAmt * 8)).sin, (oscR * (1 + foldAmt * 8)).sin], // 3: Fold
        [SyncSaw.ar(freq - spread, freq + spread), oscR],      // 4: Sync
        [oscL * oscR, oscR]                                     // 5: Ring
    ]);

    Out.ar(outBus, sig);
}).add;

// ==========================================
// PRISMATIC_MULTI — MultiWAVE
// ==========================================
// Multi-output waveform generator
SynthDef(\prismatic_multi, {
    |outBusSin=0, outBusTri=1, outBusSaw=2, outBusSq=3,
     outBusSubSin=4, outBusSubSq=5,
     freq=220|

    Out.ar(outBusSin, SinOsc.ar(freq));
    Out.ar(outBusTri, LFTri.ar(freq));
    Out.ar(outBusSaw, Saw.ar(freq));
    Out.ar(outBusSq, Pulse.ar(freq, 0.5));
    Out.ar(outBusSubSin, SinOsc.ar(freq / 2));
    Out.ar(outBusSubSq, Pulse.ar(freq / 2, 0.5));
}).add;

// ==========================================
// SPECTRAL_ORACLE — Spectraphon
// ==========================================
// Dual spectral oscillator with FFT-based resynthesis + analysis
SynthDef(\spectral_oracle, {
    |outBus=0, inBus=0,
     // Voice A: Spectral oscillator
     freqA=220, specPositionA=0, specBrightnessA=0.5,
     // Voice B: Spectral analysis/resynthesis
     freqB=220, specPositionB=0, specBrightnessB=0.5,
     // Interaction
     crossMod=0,
     // Mix
     mixA=0.5, mixB=0.5, mix=0.5|

    var inSig, chain, specA, specB, sig;

    // Voice A: additive spectral oscillator (spectral position morphs harmonics)
    specA = Mix.fill(16, { |i|
        var harmFreq = freqA * (i + 1);
        var amp = (1 / (i + 1)) * (1 - (specPositionA * i * 0.06)).max(0);
        amp = amp * (1 - ((i / 16) * (1 - specBrightnessA)));
        SinOsc.ar(harmFreq.clip(20, 20000)) * amp;
    }) / 4;

    // Voice B: FFT analysis of input → resynthesis at new pitch
    inSig = In.ar(inBus, 1);
    chain = FFT(LocalBuf(2048), inSig);

    // Spectral processing: shift bins to match target pitch
    chain = PV_BinShift(chain, freqB / 220, 0);

    // Brightness control via spectral filtering
    chain = PV_BrickWall(chain, specBrightnessB.linlin(0, 1, -0.5, 1.0));

    specB = IFFT(chain) * 0.5;

    // Cross-modulation
    specA = specA + (specB * crossMod.clip(0, 1) * 0.3);

    sig = (specA * mixA.clip(0, 1)) + (specB * mixB.clip(0, 1));

    Out.ar(outBus, XFade2.ar(inSig, sig, mix.clip(0, 1) * 2 - 1));
}).add;

// ==========================================
// HARMONIC_VESSEL — tELHARMONIC
// ==========================================
// Additive synthesis based on telharmonium, 3 algorithms
SynthDef(\harmonic_vessel, {
    |outBus=0, freq=220, gate=1,
     algorithm=0,   // 0=classic additive, 1=noise modulated, 2=subharmonic
     harmony=0.5,   // Harmonic content amount
     warp=0,        // Spectral warping
     numPartials=12|

    var sig;

    sig = Select.ar(algorithm.clip(0, 2).round, [
        // 0: Classic additive (telharmonium tone wheels)
        Mix.fill(numPartials.clip(1, 24), { |i|
            var harmFreq = freq * (i + 1);
            var amp = harmony.linlin(0, 1, 0.1, 1) / ((i + 1) ** (1 + (warp * 2)));
            SinOsc.ar(harmFreq.clip(20, 20000)) * amp;
        }) / 4,

        // 1: Noise-modulated additive
        Mix.fill(numPartials.clip(1, 24), { |i|
            var harmFreq = freq * (i + 1) + (LFNoise1.kr(3) * warp * freq * 0.1);
            var amp = harmony / ((i + 1) ** 1.5);
            SinOsc.ar(harmFreq.clip(20, 20000)) * amp;
        }) / 4,

        // 2: Subharmonic series
        Mix.fill(numPartials.clip(1, 24), { |i|
            var subFreq = freq / (i + 1);
            var amp = harmony / ((i + 1) ** (0.5 + warp));
            SinOsc.ar(subFreq.clip(20, 20000)) * amp;
        }) / 4
    ]);

    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: Make Noise Oscillator Clones Online ---".postln;
"  PRISMATIC_TWIN (DPO) | PRISMATIC_MONO (STO) | PRISMATIC_STEREO (XPO)".postln;
"  PRISMATIC_MULTI (MultiWAVE) | SPECTRAL_ORACLE (Spectraphon) | HARMONIC_VESSEL (tELHARMONIC)".postln;
)
