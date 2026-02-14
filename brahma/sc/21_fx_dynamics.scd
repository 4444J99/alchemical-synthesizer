/*
  Phase 4: CRUCIBLE — Dynamics FX
  Compressor, Limiter, Gate, Expander, Sidechain Ducker
  All follow: |inBus, outBus, mix=0.5, bypass=0| + specific params
*/

(
// ==========================================
// COMPRESSOR
// ==========================================
SynthDef(\crucible_compressor, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     threshold=(-12), ratio=4, attack=0.01, release=0.1,
     knee=6, makeup=0,
     sidechainBus=(-1)|  // -1 = use input as sidechain

    var input, sc, env, gain, compressed, sig;

    input = In.ar(inBus, 1);
    sc = if(sidechainBus >= 0, { In.ar(sidechainBus, 1) }, { input });

    env = Amplitude.kr(sc, attack.clip(0.0001, 1), release.clip(0.001, 2));
    env = env.ampdb;

    // Soft knee compression
    gain = Select.kr((env > threshold).asInteger, [
        0, // Below threshold: no reduction
        (env - threshold) * (1 - (1 / ratio.clip(1, 100))) * -1
    ]);

    compressed = input * (gain + makeup).dbamp;
    sig = XFade2.ar(input, compressed, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// LIMITER
// ==========================================
SynthDef(\crucible_limiter, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     ceiling=(-0.3), lookahead=0.005, release=0.05|

    var input, limited, sig;

    input = In.ar(inBus, 1);
    limited = Limiter.ar(input, ceiling.dbamp.clip(0.01, 1), lookahead.clip(0.001, 0.02));

    sig = XFade2.ar(input, limited, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// NOISE GATE
// ==========================================
SynthDef(\crucible_gate, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     threshold=(-40), range=(-80), attack=0.001, hold=0.05, release=0.1,
     sidechainBus=(-1)|

    var input, sc, env, gateSignal, gated, sig;

    input = In.ar(inBus, 1);
    sc = if(sidechainBus >= 0, { In.ar(sidechainBus, 1) }, { input });

    env = Amplitude.kr(sc, attack.clip(0.0001, 0.5), release.clip(0.001, 2));

    // Gate with hold time
    gateSignal = (env.ampdb > threshold);
    gateSignal = Trig1.kr(gateSignal, hold.clip(0.001, 1)) + gateSignal;
    gateSignal = gateSignal.clip(0, 1).lag(attack, release);

    // Range: how much to attenuate when gated (0 = full mute, -80dB = nearly mute)
    gated = input * gateSignal.linlin(0, 1, range.dbamp, 1);

    sig = XFade2.ar(input, gated, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// EXPANDER
// ==========================================
SynthDef(\crucible_expander, {
    |inBus=0, outBus=0, mix=1.0, bypass=0,
     threshold=(-30), ratio=2, attack=0.005, release=0.1|

    var input, env, gain, expanded, sig;

    input = In.ar(inBus, 1);
    env = Amplitude.kr(input, attack.clip(0.0001, 0.5), release.clip(0.001, 2));

    // Expand: signals below threshold are attenuated more
    gain = Select.kr((env.ampdb < threshold).asInteger, [
        0, // Above threshold: no change
        (env.ampdb - threshold) * (ratio.clip(1, 20) - 1)
    ]);

    expanded = input * gain.dbamp;
    sig = XFade2.ar(input, expanded, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

// ==========================================
// SIDECHAIN DUCKER
// ==========================================
SynthDef(\crucible_ducker, {
    |inBus=0, outBus=0, sidechainBus=0, mix=1.0, bypass=0,
     duckAmount=0.8, attack=0.005, release=0.15|

    var input, sc, env, ducked, sig;

    input = In.ar(inBus, 1);
    sc = In.ar(sidechainBus, 1);

    env = Amplitude.kr(sc, attack.clip(0.0001, 0.5), release.clip(0.001, 2));
    ducked = input * (1 - (env * duckAmount.clip(0, 1)));

    sig = XFade2.ar(input, ducked, mix.clip(0, 1) * 2 - 1);
    sig = Select.ar(bypass.clip(0, 1), [sig, input]);

    ReplaceOut.ar(outBus, sig);
}).add;

"--- BRAHMA: CRUCIBLE Dynamics FX Online (5 processors) ---".postln;
)
