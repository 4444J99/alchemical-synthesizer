/*
  Phase 2: Synthesis Engine Suite
  9 complete 7-stage organisms with standard interface:
    outBus, inBus, freq, gate, vel, pressure, slide

  Each engine is MPE-compatible, microtonal-ready, FSAP-compliant.
  Registration with AdamKadmon + Chronos targets at end of file.

  Engines:
    1. PRIMA MATERIA — Subtractive
    2. AZOTH — FM (DX7-class 4-operator)
    3. QUINTESSENCE — Additive (32 harmonics)
    4. OUROBOROS — Wavetable
    5. CHRYSOPOEIA — Phase Distortion (CZ-style)
    6. HOMUNCULUS — Physical Modeling
    7. BUCHLAEUS — West Coast Complex Oscillator
    8. LOGOS — Formant Synthesis
    9. TETRAMORPH — Vector Synthesis
*/

(
// ==========================================
// 1. PRIMA MATERIA — Subtractive Synthesis
// ==========================================
SynthDef(\prima_materia, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // Oscillators
     osc1Type=1, osc1Detune=0, osc1Level=1.0,
     osc2Type=1, osc2Detune=7, osc2Level=0.5,
     osc3Type=0, osc3Detune=0, osc3Level=0.3,
     subLevel=0.2, subOctave=1,
     pwm=0.5, hardSync=0, ringMod=0,
     // Filter
     filterType=0, cutoff=2000, resonance=2, filterEnvAmt=0.5, keyTrack=0.5,
     // Amp envelope
     atk=0.01, dec=0.3, sus=0.7, rel=0.3,
     // Filter envelope
     fAtk=0.005, fDec=0.2, fSus=0.3, fRel=0.2,
     // Unison
     unisonVoices=1, unisonDetune=0.1, unisonDrift=0.01,
     // Portamento
     portamento=0|

    var osc1, osc2, osc3, sub, mix, filter, ampEnv, fEnv, fCutoff, sig;
    var portFreq;

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
    fEnv = EnvGen.ar(Env.adsr(fAtk, fDec, fSus, fRel), gate);

    portFreq = Lag.kr(freq, portamento);

    // Oscillator 1
    osc1 = Select.ar(osc1Type.clip(0, 5), [
        SinOsc.ar(portFreq + osc1Detune),
        Saw.ar(portFreq + osc1Detune),
        Pulse.ar(portFreq + osc1Detune, pwm),
        LFTri.ar(portFreq + osc1Detune),
        Pulse.ar(portFreq + osc1Detune, 0.5), // Square
        // Super-saw: detuned saw stack
        Mix.fill(5, { |i| Saw.ar(portFreq + osc1Detune + (i - 2 * unisonDetune * 3)) }) / 5
    ]) * osc1Level;

    // Oscillator 2
    osc2 = Select.ar(osc2Type.clip(0, 3), [
        SinOsc.ar(portFreq + osc2Detune),
        Saw.ar(portFreq + osc2Detune),
        Pulse.ar(portFreq + osc2Detune, pwm),
        LFTri.ar(portFreq + osc2Detune)
    ]) * osc2Level;

    // Hard sync: osc1 resets osc2 phase (use Select.ar for runtime switching)
    osc2 = Select.ar(hardSync > 0, [
        osc2,
        SyncSaw.ar(portFreq + osc1Detune, portFreq + osc2Detune) * osc2Level
    ]);

    // Oscillator 3
    osc3 = Select.ar(osc3Type.clip(0, 3), [
        SinOsc.ar(portFreq + osc3Detune),
        Saw.ar(portFreq + osc3Detune),
        Pulse.ar(portFreq + osc3Detune, pwm),
        LFTri.ar(portFreq + osc3Detune)
    ]) * osc3Level;

    // Sub oscillator
    sub = SinOsc.ar(portFreq / (2 ** subOctave)) * subLevel;

    // Mix + ring mod
    mix = osc1 + osc2 + osc3 + sub;
    mix = XFade2.ar(mix, osc1 * osc2, ringMod.clip(0, 1) * 2 - 1);

    // Filter
    fCutoff = (cutoff + (fEnv * filterEnvAmt * 8000) + (portFreq * keyTrack)).clip(20, 20000);

    filter = Select.ar(filterType.clip(0, 3), [
        MoogFF.ar(mix, fCutoff, resonance.clip(0, 4)),
        RLPF.ar(mix, fCutoff, (1 / resonance.clip(0.5, 20)).clip(0.01, 1)),
        RHPF.ar(mix, fCutoff, (1 / resonance.clip(0.5, 20)).clip(0.01, 1)),
        BPF.ar(mix, fCutoff, (1 / resonance.clip(0.5, 20)).clip(0.01, 1))
    ]);

    sig = filter * ampEnv * velocity;
    sig = sig + (sig * pressure * 0.3); // Pressure adds gain

    Out.ar(outBus, Pan2.ar(sig, slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 2. AZOTH — FM Synthesis (4-operator)
// ==========================================
SynthDef(\azoth, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // Algorithm selection (0-7)
     algorithm=0,
     // Operator 1
     op1Ratio=1, op1Level=1.0, op1Feedback=0,
     op1Atk=0.01, op1Dec=0.5, op1Sus=0.5, op1Rel=0.3,
     // Operator 2
     op2Ratio=2, op2Level=0.5,
     op2Atk=0.01, op2Dec=0.3, op2Sus=0.3, op2Rel=0.2,
     // Operator 3
     op3Ratio=3, op3Level=0.3,
     op3Atk=0.005, op3Dec=0.2, op3Sus=0.2, op3Rel=0.15,
     // Operator 4
     op4Ratio=4, op4Level=0.2,
     op4Atk=0.005, op4Dec=0.15, op4Sus=0.1, op4Rel=0.1,
     // Operator waveforms: 0=sine, 1=tri, 2=saw, 3=square
     op1Wave=0, op2Wave=0, op3Wave=0, op4Wave=0,
     // Velocity sensitivity per operator
     op1VelSens=0.5, op2VelSens=0.5, op3VelSens=0.5, op4VelSens=0.5|

    var op1, op2, op3, op4, env1, env2, env3, env4;
    var fb, mix, sig;
    var velScale;

    env1 = EnvGen.ar(Env.adsr(op1Atk, op1Dec, op1Sus, op1Rel), gate, doneAction: 2);
    env2 = EnvGen.ar(Env.adsr(op2Atk, op2Dec, op2Sus, op2Rel), gate);
    env3 = EnvGen.ar(Env.adsr(op3Atk, op3Dec, op3Sus, op3Rel), gate);
    env4 = EnvGen.ar(Env.adsr(op4Atk, op4Dec, op4Sus, op4Rel), gate);

    velScale = { |sens| 1 - sens + (velocity * sens) };

    // Operator 4 (always a modulator or carrier depending on algorithm)
    op4 = SinOsc.ar(freq * op4Ratio) * op4Level * env4 * velScale.value(op4VelSens);

    // Operator 3
    op3 = SinOsc.ar(freq * op3Ratio + (op4 * freq * op4Ratio)) * op3Level * env3 * velScale.value(op3VelSens);

    // Operator 2
    op2 = SinOsc.ar(freq * op2Ratio + (op3 * freq * op3Ratio)) * op2Level * env2 * velScale.value(op2VelSens);

    // Feedback for operator 1
    fb = LocalIn.ar(1) * op1Feedback;

    // Operator 1
    op1 = SinOsc.ar(freq * op1Ratio + (op2 * freq * op2Ratio) + fb) * op1Level * env1 * velScale.value(op1VelSens);
    LocalOut.ar(op1);

    // Algorithm mixing (simplified: 8 common configurations)
    mix = Select.ar(algorithm.clip(0, 7), [
        op1,                              // 0: 4→3→2→1 (serial)
        op1 + op3,                        // 1: 4→3, 2→1 (two chains, mixed)
        op1 + op2,                        // 2: 4→3→2, 1 (three+one)
        op1 + op2 + op3,                  // 3: 4→{1,2,3} (one mod, three carriers)
        op1 + op2 + op3 + op4,            // 4: all carriers (additive)
        op1 + (op3 * op4),               // 5: feedback pair + ring
        (op1 + op2) * 0.5 + (op3 * 0.3), // 6: stack with blend
        op1 * 0.5 + op2 * 0.3 + op3 * 0.15 + op4 * 0.05 // 7: weighted additive
    ]);

    sig = mix * velocity;
    sig = sig + (sig * pressure * 0.2);

    Out.ar(outBus, Pan2.ar(sig, slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 3. QUINTESSENCE — Additive Synthesis (32 harmonics)
// ==========================================
SynthDef(\quintessence, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // Harmonic amplitudes (first 16, rest derived)
     h1=1.0, h2=0.5, h3=0.33, h4=0.25, h5=0.2, h6=0.17, h7=0.14, h8=0.125,
     h9=0.11, h10=0.1, h11=0.09, h12=0.08, h13=0.07, h14=0.065, h15=0.06, h16=0.055,
     // Harmonic controls
     stretch=1.0,    // Stretch ratio (1=harmonic, >1=inharmonic)
     spread=0.0,     // Frequency spread between harmonics
     shift=0.0,      // Shift all harmonics (Hz)
     // Spectral morph (mix between two profiles)
     morphTarget=0,  // 0=current, 1=all-equal, 2=odd-only, 3=even-only
     morphAmount=0,
     // Envelope
     atk=0.01, dec=0.3, sus=0.7, rel=0.3|

    var harmonics, amps, sig, ampEnv, morph;

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    amps = [h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, h13, h14, h15, h16];

    // Generate 32 harmonics (extend the 16 provided)
    harmonics = 32.collect({ |i|
        var harmFreq = freq * ((i + 1) ** stretch) + (i * spread) + shift;
        var amp = if(i < 16) { amps[i] } { 1.0 / (i + 1) };
        var oddMask = if((i % 2) == 0) { 1.0 } { 0.0 };
        var evenMask = if((i % 2) == 1) { 1.0 } { 0.0 };

        // Spectral morphing
        var morphAmp = Select.kr(morphTarget.clip(0, 3), [
            amp,
            1.0 / 32,                // All equal
            amp * oddMask,            // Odd only
            amp * evenMask            // Even only
        ]);

        amp = amp.blend(morphAmp, morphAmount);

        SinOsc.ar(harmFreq.clip(20, 20000)) * amp;
    });

    sig = Mix.new(harmonics) / 8; // Normalize

    sig = sig * ampEnv * velocity;
    sig = sig + (sig * pressure * 0.15);

    Out.ar(outBus, Pan2.ar(sig, slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 4. OUROBOROS — Wavetable Synthesis
// ==========================================
SynthDef(\ouroboros, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // Wavetable
     bufnum=0,        // Wavetable buffer (256 frames)
     position=0.0,    // Scan position (0-1)
     morph=0.0,       // Morph to second table
     bufnum2=0,       // Second wavetable buffer
     // 2D control
     posModFreq=0,    // LFO rate for position modulation
     posModAmt=0,     // Amount of position modulation
     // FM from position
     fmIndex=0,       // FM index (wavetable position FM)
     // Envelope
     atk=0.01, dec=0.3, sus=0.7, rel=0.3,
     // Filter
     cutoff=8000, resonance=1, filterEnvAmt=0,
     fAtk=0.005, fDec=0.2, fSus=0.3, fRel=0.2|

    var sig, sig2, mix, filter, ampEnv, fEnv, fCutoff;
    var posLFO, scanPos;

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
    fEnv = EnvGen.ar(Env.adsr(fAtk, fDec, fSus, fRel), gate);

    // Position modulation
    posLFO = SinOsc.kr(posModFreq) * posModAmt;
    scanPos = (position + posLFO + (SinOsc.ar(freq) * fmIndex * 0.01)).wrap(0, 1);

    // Wavetable oscillator using VOsc (interpolated between adjacent buffers)
    sig = VOsc.ar(bufnum + scanPos.clip(0, 0.99), freq);

    // Second table for morphing
    sig2 = VOsc.ar(bufnum2 + scanPos.clip(0, 0.99), freq);

    mix = XFade2.ar(sig, sig2, morph.clip(0, 1) * 2 - 1);

    // Filter
    fCutoff = (cutoff + (fEnv * filterEnvAmt * 5000)).clip(20, 20000);
    filter = MoogFF.ar(mix, fCutoff, resonance.clip(0, 4));

    filter = filter * ampEnv * velocity;

    Out.ar(outBus, Pan2.ar(filter, slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 5. CHRYSOPOEIA — Phase Distortion (CZ-style)
// ==========================================
SynthDef(\chrysopoeia, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // PD waveform type (0-7)
     pdType=0,
     // Phase distortion amount (DCW = Digital Controlled Waveshape)
     dcw=0.5,
     // Dual oscillator
     osc2Ratio=1.0, osc2Level=0, osc2Ring=0,
     // Envelope
     atk=0.01, dec=0.3, sus=0.5, rel=0.3,
     // DCW envelope
     dcwAtk=0.005, dcwDec=0.2, dcwSus=0.2, dcwRel=0.1, dcwEnvAmt=0.5|

    var phase, distorted, osc1, osc2, mix, sig, ampEnv, dcwEnv, dcwVal;

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
    dcwEnv = EnvGen.ar(Env.adsr(dcwAtk, dcwDec, dcwSus, dcwRel), gate);

    dcwVal = (dcw + (dcwEnv * dcwEnvAmt)).clip(0, 1);

    // Phase distortion: distort the phase of a cosine
    phase = Phasor.ar(0, freq * SampleDur.ir, 0, 1);

    // Apply distortion curve based on type
    distorted = Select.ar(pdType.clip(0, 7), [
        // 0: Saw (phase ramp → cosine window)
        (phase * (1 + (dcwVal * 7))).clip(0, 1).cos,
        // 1: Square (abrupt phase transition)
        ((phase * 2).clip(0, 1) * (1 + (dcwVal * 3))).clip(0, 1).cos,
        // 2: Pulse (narrow pulse via steep phase)
        (phase * (1 + (dcwVal * 15))).clip(0, 1).cos,
        // 3: Resonant saw (double-speed phase creates resonance)
        (phase * (1 + (dcwVal * 4)) + (phase.squared * dcwVal * 2)).cos,
        // 4: Resonant triangle
        (phase.fold(0, 0.5) * 2 * (1 + (dcwVal * 8))).cos,
        // 5: Resonant pulse
        (phase * (1 + (dcwVal * 12)) + SinOsc.ar(freq * 2) * dcwVal * 0.3).cos,
        // 6: Double sine
        SinOsc.ar(freq) * SinOsc.ar(freq * (1 + dcwVal)),
        // 7: Formant-like
        SinOsc.ar(freq) * (1 + (SinOsc.ar(freq * (2 + (dcwVal * 6))) * dcwVal))
    ]);

    osc1 = distorted;

    // Oscillator 2
    osc2 = SinOsc.ar(freq * osc2Ratio, phase * (1 + (dcwVal * 4))) * osc2Level;

    // Ring modulation between oscillators
    mix = XFade2.ar(osc1 + osc2, osc1 * osc2, osc2Ring.clip(0, 1) * 2 - 1);

    sig = mix * ampEnv * velocity;
    sig = sig + (sig * pressure * 0.2);

    Out.ar(outBus, Pan2.ar(LeakDC.ar(sig), slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 6. HOMUNCULUS — Physical Modeling
// ==========================================
SynthDef(\homunculus, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // Model type: 0=pluck, 1=bow, 2=blow, 3=modal, 4=membrane
     modelType=0,
     // Exciter
     exciterType=0,   // 0=noise, 1=impulse, 2=bow
     exciterBright=0.5,
     // String/tube params
     feedback=0.99,   // Resonance decay
     damping=0.3,     // High-frequency damping
     // Bow params
     bowPressure=0.5, bowPosition=0.12,
     // Breath params
     breathPressure=0.5, embouchure=0.5,
     // Modal params
     numModes=8,
     modeSpread=1.0,  // Harmonic/inharmonic spread
     // Membrane
     tension=0.5,
     // Envelope
     atk=0.005, dec=0.5, sus=0.3, rel=0.5|

    var exciter, body, sig, ampEnv;

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    // Exciter selection
    exciter = Select.ar(exciterType.clip(0, 2), [
        // Noise burst
        LPF.ar(WhiteNoise.ar, freq * (2 + (exciterBright * 8))) * EnvGen.ar(Env.perc(0.001, 0.01)),
        // Impulse
        Impulse.ar(0) * 0.5,
        // Bow (continuous noise shaped by pressure)
        LPF.ar(WhiteNoise.ar * bowPressure * gate, freq * 3) * Lag.kr(gate, 0.1)
    ]) * velocity;

    // Body model selection
    body = Select.ar(modelType.clip(0, 4), [
        // 0: Plucked string (Karplus-Strong extended)
        CombL.ar(
            exciter,
            0.05,
            freq.reciprocal,
            feedback.clip(0.1, 10) * 2
        ) |> { |s| LPF.ar(s, freq * (4 - (damping * 3)).max(1.5)) },

        // 1: Bowed string (continuous excitation with feedback network)
        {
            var bow = LPF.ar(WhiteNoise.ar * bowPressure * gate, freq * 3) * Lag.kr(gate, 0.1);
            var body = CombL.ar(
                bow + (LocalIn.ar(1) * feedback * 0.5),
                0.05, freq.reciprocal, feedback * 3
            );
            LocalOut.ar(LPF.ar(body * 0.5, freq * 2));
            body;
        }.value,

        // 2: Blown tube
        CombL.ar(
            LPF.ar(exciter * breathPressure, freq * embouchure.linexp(0, 1, 1, 8)),
            0.1,
            freq.reciprocal * 2, // Tube is half-wavelength
            feedback * 4
        ) |> { |s| LPF.ar(s, freq * 6) },

        // 3: Modal synthesis (bank of resonators)
        Mix.fill(8, { |i|
            var modeFreq = freq * ((i + 1) ** modeSpread);
            var modeDecay = feedback * (1 - (i * 0.1)).max(0.1);
            Ringz.ar(exciter, modeFreq.clip(20, 20000), modeDecay) / 8;
        }),

        // 4: Membrane (circular membrane model)
        Mix.fill(6, { |i|
            // Bessel function zero approximation for circular membrane modes
            var modeRatios = [1.0, 1.593, 2.136, 2.296, 2.653, 2.917];
            var modeFreq = freq * modeRatios[i] * tension.linexp(0, 1, 0.5, 2);
            Ringz.ar(exciter, modeFreq.clip(20, 20000), feedback * (1 - (i * 0.15)).max(0.05)) / 6;
        })
    ]);

    sig = LeakDC.ar(body) * ampEnv;
    sig = sig + (sig * pressure * 0.2);

    Out.ar(outBus, Pan2.ar(sig.clip(-1, 1), slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 7. BUCHLAEUS — West Coast Complex Oscillator
// ==========================================
SynthDef(\buchlaeus, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // Primary oscillator
     primaryWave=0,   // 0=sine, 1=tri, 2=saw, 3=square
     // Modulation oscillator
     modWave=0,       // 0=sine, 1=tri, 2=saw, 3=square
     modRatio=2.0,    // Frequency ratio
     // FM
     fmIndex=0.0,     // Through-zero FM index
     // Timbre (AM + wavefold combined)
     timbre=0.0,
     // Wavefolder
     foldAmount=0.0,  // 0-1
     foldSymmetry=0.5, // Asymmetric folding
     foldStages=3,    // 1-8 fold stages
     // Envelope
     atk=0.01, dec=0.3, sus=0.7, rel=0.3|

    var primary, modOsc, fm, timbreAM, folded, sig, ampEnv;

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    // Modulation oscillator
    modOsc = Select.ar(modWave.clip(0, 3), [
        SinOsc.ar(freq * modRatio),
        LFTri.ar(freq * modRatio),
        Saw.ar(freq * modRatio),
        Pulse.ar(freq * modRatio, 0.5)
    ]);

    // Through-zero FM
    fm = freq + (modOsc * freq * fmIndex);

    // Primary oscillator (FM'd)
    primary = Select.ar(primaryWave.clip(0, 3), [
        SinOsc.ar(fm),
        LFTri.ar(fm),
        Saw.ar(fm),
        Pulse.ar(fm, 0.5)
    ]);

    // Timbre modulation (AM component)
    timbreAM = primary * (1 + (modOsc * timbre));

    // Wavefolder (cascaded sine-fold stages)
    folded = timbreAM;
    foldStages.clip(1, 8).do({
        var gain = 1 + (foldAmount * 3);
        var bias = (foldSymmetry - 0.5) * 0.5;
        folded = ((folded + bias) * gain).sin;
    });

    sig = XFade2.ar(primary, folded, foldAmount.clip(0, 1) * 2 - 1);

    sig = sig * ampEnv * velocity;
    sig = sig + (sig * pressure * 0.3);

    Out.ar(outBus, Pan2.ar(LeakDC.ar(sig), slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 8. LOGOS — Formant Synthesis
// ==========================================
SynthDef(\logos, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // Vowel morph (0=A, 0.25=E, 0.5=I, 0.75=O, 1.0=U)
     vowel=0.0,
     // Formant filter params (5 parallel resonators)
     f1Freq=800, f1Bw=80, f1Amp=1.0,
     f2Freq=1200, f2Bw=90, f2Amp=0.5,
     f3Freq=2500, f3Bw=120, f3Amp=0.3,
     f4Freq=3500, f4Bw=150, f4Amp=0.2,
     f5Freq=4500, f5Bw=200, f5Amp=0.1,
     // Excitation type: 0=glottal, 1=noise, 2=external
     exciterType=0,
     // Choir mode
     choirVoices=1, choirDetune=0.02,
     // Envelope
     atk=0.01, dec=0.3, sus=0.7, rel=0.3|

    var exciter, formants, sig, ampEnv;
    var vowelFreqs, vowelBWs;

    // Vowel formant data (approximate) — interpolated by vowel param
    // A:    [800, 1200, 2500, 3500, 4500]
    // E:    [400, 2200, 2800, 3500, 4500]
    // I:    [350, 2300, 3000, 3700, 4500]
    // O:    [500, 800,  2500, 3500, 4500]
    // U:    [350, 700,  2500, 3500, 4500]

    vowelFreqs = [
        // f1
        Select.kr((vowel * 4).clip(0, 4).round, [800, 400, 350, 500, 350]),
        // f2
        Select.kr((vowel * 4).clip(0, 4).round, [1200, 2200, 2300, 800, 700]),
        // f3
        Select.kr((vowel * 4).clip(0, 4).round, [2500, 2800, 3000, 2500, 2500]),
        2500 + (f4Freq - 2500), // f4 mostly stable
        4500 + (f5Freq - 4500)  // f5 mostly stable
    ];

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    // Exciter
    exciter = Select.ar(exciterType.clip(0, 2), [
        // Glottal pulse (impulse train with some breathiness)
        Impulse.ar(freq) + (PinkNoise.ar * 0.05),
        // Noise
        PinkNoise.ar * 0.5,
        // External input
        In.ar(inBus, 1)
    ]);

    // 5 parallel formant filters
    formants = [
        BPF.ar(exciter, vowelFreqs[0].clip(80, 10000), f1Bw.reciprocal.clip(0.001, 0.5)) * f1Amp,
        BPF.ar(exciter, vowelFreqs[1].clip(80, 10000), f2Bw.reciprocal.clip(0.001, 0.5)) * f2Amp,
        BPF.ar(exciter, vowelFreqs[2].clip(80, 10000), f3Bw.reciprocal.clip(0.001, 0.5)) * f3Amp,
        BPF.ar(exciter, vowelFreqs[3].clip(80, 10000), f4Bw.reciprocal.clip(0.001, 0.5)) * f4Amp,
        BPF.ar(exciter, vowelFreqs[4].clip(80, 10000), f5Bw.reciprocal.clip(0.001, 0.5)) * f5Amp
    ];

    sig = Mix.new(formants) * 4; // Boost narrow BPF output

    // Choir mode: stack 6 detuned voices, use amplitude gating for count
    sig = Select.ar(choirVoices > 1, [
        sig,
        Mix.fill(6, { |i|
            var active = (i < choirVoices).asInteger;
            var detune = (i - 3) * choirDetune * freq;
            var choirExciter = Impulse.ar(freq + detune) + (PinkNoise.ar * 0.03);
            var choirFormants = formants.collect({ |f, fi|
                BPF.ar(choirExciter, vowelFreqs[fi].clip(80, 10000),
                    [f1Bw, f2Bw, f3Bw, f4Bw, f5Bw][fi].reciprocal.clip(0.001, 0.5))
            });
            Mix.new(choirFormants) * active;
        }) * (4 / choirVoices.clip(1, 6))
    ]);

    sig = sig * ampEnv * velocity;

    Out.ar(outBus, Pan2.ar(LeakDC.ar(sig.clip(-1, 1)), slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 9. TETRAMORPH — Vector Synthesis
// ==========================================
SynthDef(\tetramorph, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // XY position for 4-corner crossfade
     vectorX=0.5, vectorY=0.5,
     // Source types: 0=sine, 1=saw, 2=square, 3=tri, 4=noise, 5=FM
     srcN=0, srcS=1, srcE=2, srcW=3,
     // Per-source detune
     detuneN=0, detuneS=5, detuneE=-5, detuneW=3,
     // Per-source ratio
     ratioN=1, ratioS=1, ratioE=2, ratioW=0.5,
     // Envelope
     atk=0.01, dec=0.3, sus=0.7, rel=0.3,
     // Filter
     cutoff=5000, resonance=1|

    var north, south, east, west, mix, sig, ampEnv;
    var makeOsc;

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    // Helper: create oscillator by type
    makeOsc = { |type, f|
        Select.ar(type.clip(0, 5), [
            SinOsc.ar(f),
            Saw.ar(f),
            Pulse.ar(f, 0.5),
            LFTri.ar(f),
            PinkNoise.ar,
            SinOsc.ar(f + (SinOsc.ar(f * 2) * f * 0.5)) // Simple FM
        ]);
    };

    north = makeOsc.value(srcN, freq * ratioN + detuneN);
    south = makeOsc.value(srcS, freq * ratioS + detuneS);
    east  = makeOsc.value(srcE, freq * ratioE + detuneE);
    west  = makeOsc.value(srcW, freq * ratioW + detuneW);

    // Bilinear interpolation (2D crossfade)
    // vectorX: 0=west, 1=east
    // vectorY: 0=south, 1=north
    mix = LinXFade2.ar(
        LinXFade2.ar(south, north, vectorY.clip(0, 1) * 2 - 1), // Left column
        LinXFade2.ar(west, east, vectorY.clip(0, 1) * 2 - 1),   // Right column
        vectorX.clip(0, 1) * 2 - 1
    );

    // Filter
    sig = RLPF.ar(mix, cutoff.clip(20, 20000), (1 / resonance.clip(0.5, 20)).clip(0.01, 1));

    sig = sig * ampEnv * velocity;

    Out.ar(outBus, Pan2.ar(sig, slide.linlin(0, 1, -0.5, 0.5)));
}).add;

// ==========================================
// 10. NEBULA — Granular Cloud Synthesis
// ==========================================
SynthDef(\nebula, {
    |outBus=0, inBus=0, freq=440, gate=1, velocity=0.8,
     pressure=0, slide=0,
     // Buffer source (0 = use internal oscillator as grain source)
     bufnum=0, useBuffer=0,
     // Grain parameters
     grainDensity=20,       // Grains per second (1-200)
     grainSize=0.05,        // Duration of each grain (0.001-0.5s)
     position=0.0,          // Scan position in buffer (0-1)
     positionSpread=0.02,   // Random offset around position (spray)
     // Pitch
     pitchSpread=0.0,       // Random pitch deviation per grain (semitones)
     // Grain envelope shape: 0=Hanning, 1=triangle, 2=rectangular
     grainEnvType=0,
     // Stereo spread
     stereoSpread=0.5,      // 0=mono center, 1=full stereo scatter
     // Freeze: hold grains at current position
     freeze=0,
     // Texture controls
     overlap=2.0,           // Grain overlap factor
     jitter=0.0,            // Timing jitter on grain triggers (0-1)
     // Filter
     cutoff=12000, resonance=0.5,
     // Envelope
     atk=0.1, dec=0.3, sus=0.8, rel=0.5|

    var trig, grainTrig, grainPos, grainPitch, grainDur;
    var grainSig, oscSource, ampEnv, sig;
    var pitchRand, panRand, posJitter;
    var grainEnv;

    ampEnv = EnvGen.ar(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);

    // Grain trigger: density with optional jitter
    grainTrig = Impulse.ar(grainDensity.clip(1, 200))
        + (Dust.ar(grainDensity * jitter.clip(0, 1)) * jitter.sign);

    // Grain duration
    grainDur = grainSize.clip(0.001, 0.5) * overlap.clip(0.5, 8);

    // Per-grain random pitch deviation
    pitchRand = TRand.ar(
        pitchSpread.clip(0, 24).neg,
        pitchSpread.clip(0, 24),
        grainTrig
    );
    grainPitch = (2 ** (pitchRand / 12));

    // Per-grain pan position
    panRand = TRand.ar(
        stereoSpread.clip(0, 1).neg,
        stereoSpread.clip(0, 1),
        grainTrig
    );

    // Position with spray/spread
    posJitter = TRand.ar(
        positionSpread.clip(0, 0.5).neg,
        positionSpread.clip(0, 0.5),
        grainTrig
    );
    grainPos = Select.ar(freeze.clip(0, 1), [
        (position + posJitter).wrap(0, 1),
        position  // Frozen: no position movement
    ]);

    // Grain envelope selection
    grainEnv = Select.kr(grainEnvType.clip(0, 2), [
        -1,  // Hanning (built-in)
        -1,  // Triangle (use built-in, closest)
        -1   // Rectangular (use built-in)
    ]);

    // Select grain source: buffer or synthesis
    grainSig = Select.ar(useBuffer.clip(0, 1), [
        // Synthesis-based grains (GrainSin)
        GrainSin.ar(
            numChannels: 2,
            trigger: grainTrig,
            dur: grainDur,
            freq: freq * grainPitch,
            pan: panRand
        ),
        // Buffer-based grains (GrainBuf)
        GrainBuf.ar(
            numChannels: 2,
            trigger: grainTrig,
            dur: grainDur,
            sndbuf: bufnum,
            rate: (freq / 440) * grainPitch * BufRateScale.ir(bufnum),
            pos: grainPos,
            interp: 4,
            pan: panRand
        )
    ]);

    // Filter
    sig = RLPF.ar(grainSig, cutoff.clip(20, 20000),
        (1 / resonance.clip(0.5, 20)).clip(0.01, 1));

    sig = sig * ampEnv * velocity;
    sig = sig + (sig * pressure * 0.2);

    // Slide controls stereo image shift
    sig = Balance2.ar(sig[0], sig[1], slide.linlin(0, 1, -0.5, 0.5));

    Out.ar(outBus, sig);
}).add;

// ==========================================
// ENTITY REGISTRATION & CHRONOS TARGETS
// ==========================================

// Register all engines with AdamKadmon (differentiated trait maps)
[
    [\prima_materia, "Subtractive", 3001,
        (centroid: 0.4, flatness: 0.2, bandwidth: 0.7, rolloff: 0.6),
        (attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.3, slew: 0.5)],
    [\azoth, "FM", 3002,
        (centroid: 0.7, flatness: 0.5, bandwidth: 0.9, rolloff: 0.3),
        (attack: 0.01, decay: 0.5, sustain: 0.5, release: 0.3, slew: 0.2)],
    [\quintessence, "Additive", 3003,
        (centroid: 0.6, flatness: 0.8, bandwidth: 0.5, rolloff: 0.4),
        (attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.3, slew: 0.8)],
    [\ouroboros, "Wavetable", 3004,
        (centroid: 0.5, flatness: 0.4, bandwidth: 0.6, rolloff: 0.5),
        (attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.3, slew: 0.6)],
    [\chrysopoeia, "Phase Distortion", 3005,
        (centroid: 0.6, flatness: 0.3, bandwidth: 0.7, rolloff: 0.4),
        (attack: 0.005, decay: 0.2, sustain: 0.5, release: 0.3, slew: 0.3)],
    [\homunculus, "Physical Modeling", 3006,
        (centroid: 0.3, flatness: 0.1, bandwidth: 0.4, rolloff: 0.8),
        (attack: 0.005, decay: 0.5, sustain: 0.3, release: 0.5, slew: 0.9)],
    [\buchlaeus, "West Coast", 3007,
        (centroid: 0.8, flatness: 0.6, bandwidth: 0.9, rolloff: 0.2),
        (attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.3, slew: 0.4)],
    [\logos, "Formant", 3008,
        (centroid: 0.5, flatness: 0.2, bandwidth: 0.3, rolloff: 0.7),
        (attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.3, slew: 0.7)],
    [\tetramorph, "Vector", 3009,
        (centroid: 0.5, flatness: 0.4, bandwidth: 0.6, rolloff: 0.5),
        (attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.3, slew: 0.5)],
    [\nebula, "Granular", 3010,
        (centroid: 0.4, flatness: 0.7, bandwidth: 0.8, rolloff: 0.3),
        (attack: 0.1, decay: 0.3, sustain: 0.8, release: 0.5, slew: 0.6)]
].do({ |spec|
    var synthDef = spec[0];
    var type = spec[1];
    var id = spec[2];
    var spectral = spec[3];
    var temporal = spec[4];

    // Register with AdamKadmon (unique traits per engine)
    ~BRAHMA_REGISTRY.registerEntity(id, type, (
        spectral_profile: spectral,
        temporal_topology: temporal,
        modulation_graph: (type: synthDef, sources: 0, dests: 0, routes: 0),
        performance_response: (velocity: 0.8, aftertouch: 0.5, xy_sensitivity: 0.5, humanize: 0.0)
    ));

    // Register as Chronos target
    ~CHRONOS.registerTarget(synthDef.asString, synthDef, 0, ~SC_GRP[\te]);
});

"--- BRAHMA: 10 Synthesis Engines Online ---".postln;
"  PRIMA MATERIA (Subtractive) | AZOTH (FM) | QUINTESSENCE (Additive)".postln;
"  OUROBOROS (Wavetable) | CHRYSOPOEIA (PD) | HOMUNCULUS (Physical)".postln;
"  BUCHLAEUS (West Coast) | LOGOS (Formant) | TETRAMORPH (Vector)".postln;
"  NEBULA (Granular)".postln;

// ==========================================
// PATCH BAY REGISTRATION — Synthesis Engines
// ==========================================
// Register key parameters as patchable destinations
[
    [\prima_materia, [
        [\cutoff, "Filter cutoff"], [\resonance, "Filter resonance"],
        [\osc1Detune, "Osc1 detune"], [\osc2Detune, "Osc2 detune"],
        [\pwm, "Pulse width"], [\filterEnvAmt, "Filter env amount"],
        [\portamento, "Portamento time"]
    ]],
    [\azoth, [
        [\algorithm, "FM algorithm"], [\op1Ratio, "Op1 ratio"], [\op2Ratio, "Op2 ratio"],
        [\op3Ratio, "Op3 ratio"], [\op4Ratio, "Op4 ratio"],
        [\op1Feedback, "Op1 feedback"], [\op1Level, "Op1 level"]
    ]],
    [\quintessence, [
        [\stretch, "Harmonic stretch"], [\spread, "Frequency spread"],
        [\shift, "Harmonic shift"], [\morphTarget, "Morph target"],
        [\morphAmount, "Morph amount"]
    ]],
    [\ouroboros, [
        [\position, "Wavetable position"], [\morph, "Table morph"],
        [\posModFreq, "Position LFO rate"], [\posModAmt, "Position LFO amount"],
        [\fmIndex, "FM index"], [\cutoff, "Filter cutoff"]
    ]],
    [\chrysopoeia, [
        [\pdType, "PD waveform type"], [\dcw, "DCW amount"],
        [\osc2Ratio, "Osc2 ratio"], [\osc2Ring, "Ring mod amount"],
        [\dcwEnvAmt, "DCW env amount"]
    ]],
    [\homunculus, [
        [\modelType, "Model type"], [\exciterType, "Exciter type"],
        [\exciterBright, "Exciter brightness"], [\feedback, "Resonance decay"],
        [\damping, "HF damping"], [\bowPressure, "Bow pressure"],
        [\tension, "Membrane tension"]
    ]],
    [\buchlaeus, [
        [\fmIndex, "FM index"], [\timbre, "Timbre (AM)"],
        [\foldAmount, "Fold amount"], [\foldSymmetry, "Fold symmetry"],
        [\modRatio, "Mod oscillator ratio"]
    ]],
    [\logos, [
        [\vowel, "Vowel morph"], [\f1Freq, "Formant 1 freq"],
        [\f2Freq, "Formant 2 freq"], [\exciterType, "Exciter type"],
        [\choirVoices, "Choir voices"]
    ]],
    [\tetramorph, [
        [\vectorX, "Vector X position"], [\vectorY, "Vector Y position"],
        [\cutoff, "Filter cutoff"], [\resonance, "Filter resonance"]
    ]],
    [\nebula, [
        [\grainDensity, "Grain density"], [\grainSize, "Grain size"],
        [\position, "Buffer position"], [\positionSpread, "Position spray"],
        [\pitchSpread, "Pitch spread"], [\stereoSpread, "Stereo spread"],
        [\freeze, "Freeze"], [\cutoff, "Filter cutoff"]
    ]]
].do({ |engineSpec|
    var synthName = engineSpec[0];
    var params = engineSpec[1];
    params.do({ |paramSpec|
        var paramName = paramSpec[0];
        var desc = paramSpec[1];
        ~PATCH_BAY.registerDestination(
            (synthName.asString ++ "_" ++ paramName.asString).asSymbol,
            paramName,
            synthName.asString ++ " " ++ desc
        );
    });
});
)

