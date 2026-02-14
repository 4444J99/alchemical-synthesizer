/*
  Phase 3: Make Noise Utility & Instrument Clones
  modDemix, X-PAN, XOH, Dynamix, Rosie, Wogglebug,
  Strega, 0-Coast, Bruxa
*/

(
// ==========================================
// ELIXIR_BLEND — modDemix (VC Crossfader/VCA)
// ==========================================
SynthDef(\elixir_blend, {
    |inBusA=0, inBusB=1, outBus=0, directOutA=0, directOutB=1,
     crossfade=0.5, cvBus=0, cvAmt=0|

    var a, b, cv, xf, sigA, sigB, mix;

    a = In.ar(inBusA, 1);
    b = In.ar(inBusB, 1);
    cv = In.kr(cvBus, 1) * cvAmt;

    xf = (crossfade + cv).clip(0, 1);

    sigA = a * (1 - xf);
    sigB = b * xf;
    mix = sigA + sigB;

    Out.ar(outBus, mix);
    Out.ar(directOutA, sigA);
    Out.ar(directOutB, sigB);
}).add;

// ==========================================
// ELIXIR_COMPASS — X-PAN (Stereo Crossfader/Panner)
// ==========================================
SynthDef(\elixir_compass, {
    |inBusA=0, inBusB=1, outBus=0,
     crossfade=0.5, pan=0, cvBus=0, cvAmt=0|

    var a, b, cv, xf, mix;

    a = In.ar(inBusA, 1);
    b = In.ar(inBusB, 1);
    cv = In.kr(cvBus, 1) * cvAmt;

    xf = (crossfade + cv).clip(0, 1);
    mix = XFade2.ar(a, b, xf * 2 - 1);

    Out.ar(outBus, Pan2.ar(mix, pan.clip(-1, 1)));
}).add;

// ==========================================
// ELIXIR_CROWN — XOH (Output/Headphone)
// ==========================================
SynthDef(\elixir_crown, {
    |inBusA=0, inBusB=1, outBus=0, hpBus=2,
     crossfade=0.5, mainLevel=1.0, hpLevel=0.8|

    var a, b, mix;

    a = In.ar(inBusA, 1);
    b = In.ar(inBusB, 1);

    mix = XFade2.ar(a, b, crossfade.clip(0, 1) * 2 - 1);

    Out.ar(outBus, Pan2.ar(mix * mainLevel.clip(0, 2)));
    Out.ar(hpBus, Pan2.ar(mix * hpLevel.clip(0, 2)));
}).add;

// ==========================================
// ELIXIR_FLUX — Dynamix (Dynamics-Controlled Mixer)
// ==========================================
SynthDef(\elixir_flux, {
    |inBus1=0, inBus2=1, sidechainBus=2, outBus=0,
     level1=1, level2=1, duckAmt=0.5, duckAtk=0.005, duckRel=0.1|

    var sig1, sig2, sc, env, duck;

    sig1 = In.ar(inBus1, 1) * level1;
    sig2 = In.ar(inBus2, 1) * level2;
    sc = In.ar(sidechainBus, 1);

    env = Amplitude.kr(sc, duckAtk, duckRel);
    duck = 1 - (env * duckAmt.clip(0, 1));

    Out.ar(outBus, (sig1 + (sig2 * duck)));
}).add;

// ==========================================
// ELIXIR_GATE — Rosie (Output with Send/Return)
// ==========================================
SynthDef(\elixir_gate, {
    |inBus=0, outBus=0, sendBus=2, returnBus=3,
     mainLevel=1, sendLevel=0.5, returnLevel=0.5|

    var sig, returned;

    sig = In.ar(inBus, 1);
    returned = In.ar(returnBus, 1) * returnLevel;

    // Send tap (pre-fader)
    Out.ar(sendBus, sig * sendLevel);

    // Main out with return mixed in
    Out.ar(outBus, Pan2.ar((sig * mainLevel) + returned));
}).add;

// ==========================================
// CHAOS_ORACLE — Wogglebug (Random Voltage Generator)
// ==========================================
SynthDef(\chaos_oracle, {
    |outBusSmooth=0, outBusStepped=1, outBusWoggle=2,
     outBusClock=3, outBusBurst=4,
     clockRate=4, woggleRate=2, burstDensity=0.3|

    var clock, smooth, stepped, woggle, burst;

    // Clock output
    clock = Impulse.kr(clockRate.clip(0.1, 100));
    Out.kr(outBusClock, clock);

    // Smooth random (filtered noise)
    smooth = LFNoise1.kr(woggleRate.clip(0.01, 50));
    Out.kr(outBusSmooth, smooth.unipolar);

    // Stepped random (sample & hold)
    stepped = Latch.kr(WhiteNoise.kr, clock);
    Out.kr(outBusStepped, stepped.unipolar);

    // Woggle (stepped random with slew — signature Wogglebug sound)
    woggle = Latch.kr(WhiteNoise.kr, Impulse.kr(woggleRate));
    woggle = Lag.kr(woggle, 1 / woggleRate);
    Out.kr(outBusWoggle, woggle.unipolar);

    // Burst output (random trigger burst)
    burst = Dust.kr(burstDensity.clip(0, 100));
    Out.kr(outBusBurst, burst);
}).add;

// ==========================================
// STREGA_VESSEL — Strega (Delay/Filter Instrument)
// ==========================================
SynthDef(\strega_vessel, {
    |outBus=0, inBus=0,
     freq=200, gate=1,
     // Oscillator
     oscLevel=0.5, oscType=0,
     // Delay + filter
     delayTime=0.3, feedback=0.6, filterFreq=1000,
     // Spring tank simulation
     springMix=0.3, springDecay=2.0,
     // Touch (CV input)
     touchCV=0|

    var osc, input, delayed, filtered, spring, sig, ampEnv;

    ampEnv = EnvGen.ar(Env.adsr(0.01, 0.3, 0.7, 0.5), gate, doneAction: 2);

    // Internal oscillator
    osc = Select.ar(oscType.clip(0, 2), [
        SinOsc.ar(freq),
        LFTri.ar(freq),
        Saw.ar(freq)
    ]) * oscLevel;

    // External input
    input = In.ar(inBus, 1);

    // Mix sources
    sig = osc + input;

    // Delay with feedback + filter in loop
    delayed = CombL.ar(
        LPF.ar(sig + (LocalIn.ar(1) * feedback.clip(0, 0.95)),
            (filterFreq + (touchCV * 2000)).clip(50, 15000)),
        2.0,
        delayTime.clip(0.01, 2.0),
        feedback.clip(0, 0.95) * 5
    );
    LocalOut.ar(delayed * 0.5);

    // Spring tank simulation (short dense reverb)
    spring = Mix.fill(4, { |i|
        AllpassL.ar(delayed, 0.05,
            rrand(0.01, 0.04) * (i + 1),
            springDecay.clip(0.1, 5));
    }) / 4;

    sig = delayed + (spring * springMix.clip(0, 1));
    sig = sig * ampEnv;

    Out.ar(outBus, Pan2.ar(LeakDC.ar(sig.clip(-1, 1))));
}).add;

// ==========================================
// COAST_ZERO — 0-COAST (Semi-Modular Monosynth)
// ==========================================
// Complete voice: oscillator + slope gen + dynamics + multiply
SynthDef(\coast_zero, {
    |outBus=0, freq=220, gate=1, velocity=0.8,
     // Oscillator (triangle core with overtone)
     overtone=0.5, multiply=0,
     // Slope generator (as envelope)
     slopeRise=0.01, slopeFall=0.3, slopeCycle=0,
     // Dynamics (vactrol LPG)
     dynAmount=0.8,
     // Contour (second envelope)
     contourAtk=0.01, contourDec=0.5,
     // Balance (osc mix point)
     balance=0.5|

    var tri, over, slope, contour, lpg, sig;
    var vactrolDecay;

    // Triangle core oscillator
    tri = LFTri.ar(freq);

    // Overtone circuit (wavefold for harmonic enrichment)
    over = (tri * (1 + (overtone.clip(0, 1) * 6))).sin;

    // Multiply (ring mod between tri and overtone)
    sig = XFade2.ar(tri, over * tri, multiply.clip(0, 1) * 2 - 1);

    // Balance: mix point between fundamental and overtone
    sig = XFade2.ar(tri, sig, balance.clip(0, 1) * 2 - 1);

    // Slope generator (rise/fall function gen used as envelope)
    slope = EnvGen.ar(Env.new(
        [0, 1, dynAmount.clip(0, 1), 0],
        [slopeRise.clip(0.001, 10), 0.001, slopeFall.clip(0.001, 10)],
        [\lin, \lin, \exp]
    ), gate, doneAction: 2);

    // Contour (second envelope)
    contour = EnvGen.ar(Env.perc(contourAtk, contourDec), gate);

    // Vactrol LPG simulation
    vactrolDecay = Rand(0.05, 0.3); // Per-instance variance
    lpg = Lag.ar(slope, vactrolDecay);

    // Apply dynamics: both amplitude and filter
    sig = LPF.ar(sig, (lpg * 8000 + 200).clip(50, 15000));
    sig = sig * lpg * velocity;

    Out.ar(outBus, Pan2.ar(sig));
}).add;

// ==========================================
// BRUXA_SIGIL — Bruxa (Analog Stereo Delay + Touch)
// ==========================================
SynthDef(\bruxa_sigil, {
    |outBus=0, inBus=0,
     delayTimeL=0.3, delayTimeR=0.4,
     feedback=0.5, filterFreq=3000,
     touchCV=0, saturation=0.3, mix=0.5|

    var input, delL, delR, fb, sig;

    input = In.ar(inBus, 1);

    // Feedback with filtering and saturation
    fb = LocalIn.ar(2);
    fb = LPF.ar(fb, (filterFreq + (touchCV * 3000)).clip(100, 15000));
    fb = (fb * (1 + (saturation * 4))).tanh;

    // Stereo delays
    delL = DelayL.ar(input + (fb[0] * feedback.clip(0, 0.95)),
        2.0, delayTimeL.clip(0.01, 2.0));
    delR = DelayL.ar(input + (fb[1] * feedback.clip(0, 0.95)),
        2.0, delayTimeR.clip(0.01, 2.0));

    LocalOut.ar([delR, delL]); // Cross-feedback

    sig = XFade2.ar(
        Pan2.ar(input),
        [delL, delR],
        mix.clip(0, 1) * 2 - 1
    );

    Out.ar(outBus, LeakDC.ar(sig));
}).add;

"--- BRAHMA: Make Noise Utility & Instrument Clones Online ---".postln;
"  ELIXIR_BLEND (modDemix) | ELIXIR_COMPASS (X-PAN) | ELIXIR_CROWN (XOH)".postln;
"  ELIXIR_FLUX (Dynamix) | ELIXIR_GATE (Rosie) | CHAOS_ORACLE (Wogglebug)".postln;
"  STREGA_VESSEL (Strega) | COAST_ZERO (0-Coast) | BRUXA_SIGIL (Bruxa)".postln;
)
