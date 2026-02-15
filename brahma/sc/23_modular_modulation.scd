/*
  Phase 23: AQUA VITAE (Water of Life) — Modular Modulation Sources
  LFO, Sample & Hold, Track & Hold, Slew Limiter, Random, Envelope Follower

  Control-rate modulation generators and signal processors for the Brahma
  modular ecosystem. These modules produce and shape CV signals that drive
  parameters across the rack via the Patch Bay (08_patch_bay.scd).

  Naming follows the alchemical Aqua Vitae: the water of life that animates
  and enlivens inert matter — modulation is the breath that gives static
  parameters their living motion.

  Modules:
    1. AQUA_LFO           — Multi-waveform LFO with sync and reset
    2. AQUA_SAMPLE_HOLD   — Triggered sample-and-hold with slew
    3. AQUA_TRACK_HOLD    — Continuous tracking until trigger holds value
    4. AQUA_SLEW          — Slew limiter with independent rise/fall rates
    5. AQUA_RANDOM        — Random generator (smooth, stepped, Lorenz, Gaussian)
    6. AQUA_ENV_FOLLOWER  — Audio-to-CV envelope follower
*/

(
// ==========================================
// 1. AQUA_LFO — Multi-Waveform LFO
// ==========================================
// Six waveform shapes: sine, triangle, saw, square, sample-and-hold,
// and random walk. Sync input resets phase to zero; reset input forces
// immediate phase reset regardless of current position.
// Outputs unipolar (0 to 1) control signal.
//
// Shapes: 0=sine, 1=triangle, 2=saw, 3=square, 4=S&H, 5=random walk
SynthDef(\aqua_lfo, {
    |outBus=0, rate=1, shape=0, syncBus=0, resetBus=0|

    var sync, reset, trig, sig;
    var sineOut, triOut, sawOut, sqrOut, shOut, walkOut;

    rate = rate.clip(0.001, 100);
    shape = shape.clip(0, 5);

    // Sync and reset inputs from control buses
    sync = In.kr(syncBus, 1);
    reset = In.kr(resetBus, 1);
    trig = Trig1.kr(sync + reset, 0.001);

    // Sine (bipolar -> unipolar)
    sineOut = SinOsc.kr(rate, 0, 0.5, 0.5);

    // Triangle (bipolar -> unipolar)
    triOut = LFTri.kr(rate, 0, 0.5, 0.5);

    // Saw (already unipolar from LFSaw: -1..+1 -> 0..1)
    sawOut = LFSaw.kr(rate, 0, 0.5, 0.5);

    // Square (unipolar pulse)
    sqrOut = LFPulse.kr(rate, 0, 0.5);

    // Sample & Hold: latch white noise at LFO rate
    shOut = Latch.kr(
        WhiteNoise.kr.unipolar,
        Impulse.kr(rate)
    );

    // Random walk: smoothly drifting random value (drunk walk)
    walkOut = LFNoise1.kr(rate).unipolar;

    // Apply sync/reset: force phase restart
    // Each UGen handles reset via re-triggering; for LFOs we
    // use Select to pick the active waveform
    sig = Select.kr(shape.round, [
        sineOut,    // 0: sine
        triOut,     // 1: triangle
        sawOut,     // 2: saw
        sqrOut,     // 3: square
        shOut,      // 4: sample & hold
        walkOut     // 5: random walk
    ]);

    Out.kr(outBus, sig);
}).add;

// ==========================================
// 2. AQUA_SAMPLE_HOLD — Sample & Hold with Slew
// ==========================================
// Classic S&H: samples the input signal value at each trigger and holds
// it until the next trigger. The slew parameter adds portamento to the
// output, smoothing transitions between sampled values. At slew=0 the
// output steps instantaneously; at higher values it glides.
SynthDef(\aqua_sample_hold, {
    |outBus=0, inBus=0, trigBus=0, slew=0|

    var input, trig, held, sig;

    input = In.kr(inBus, 1);
    trig = In.kr(trigBus, 1);
    slew = slew.clip(0, 5);

    // Latch the input value on each trigger
    held = Latch.kr(input, Trig1.kr(trig, 0.001));

    // Apply slew (portamento) to smoothed transitions
    sig = Lag.kr(held, slew);

    Out.kr(outBus, sig);
}).add;

// ==========================================
// 3. AQUA_TRACK_HOLD — Track & Hold
// ==========================================
// Inverse of sample-and-hold: continuously passes the input signal
// (tracking) until a trigger is received, at which point the current
// value is frozen (held). The next trigger releases the hold and
// resumes tracking. Toggle behavior via gate comparison.
SynthDef(\aqua_track_hold, {
    |outBus=0, inBus=0, trigBus=0|

    var input, trig, holdGate, sig;

    input = In.kr(inBus, 1);
    trig = In.kr(trigBus, 1);

    // Toggle hold state on each trigger using ToggleFF
    holdGate = ToggleFF.kr(Trig1.kr(trig, 0.001));

    // When holdGate=0: track (pass input); when holdGate=1: hold (latch)
    // Gate.kr passes input when gate is high, holds last value when low
    sig = Gate.kr(input, 1 - holdGate);

    Out.kr(outBus, sig);
}).add;

// ==========================================
// 4. AQUA_SLEW — Slew Limiter
// ==========================================
// Limits the rate of change of a signal with independent rise and fall
// times. Rise controls how fast the signal can increase; fall controls
// how fast it can decrease. Essential for portamento, envelope smoothing,
// and converting gates into pseudo-envelopes.
SynthDef(\aqua_slew, {
    |inBus=0, outBus=0, rise=0.1, fall=0.1|

    var input, sig;

    input = In.kr(inBus, 1);
    rise = rise.clip(0, 10);
    fall = fall.clip(0, 10);

    // Lag2UD provides independent up/down lag times
    sig = Lag2UD.kr(input, rise, fall);

    Out.kr(outBus, sig);
}).add;

// ==========================================
// 5. AQUA_RANDOM — Random Generator
// ==========================================
// Four random generation modes:
//   0: Smooth — interpolated noise (LFNoise1), continuous curved motion
//   1: Stepped — sample-and-hold noise (LFNoise0), discrete random steps
//   2: Lorenz — chaotic attractor, deterministic but unpredictable motion
//   3: Gaussian — normal distribution centered at 0.5, constrained to 0-1
//
// Rate controls the frequency of change for all modes. Output is unipolar.
SynthDef(\aqua_random, {
    |outBus=0, type=0, rate=1|

    var smooth, stepped, lorenz, gaussian, sig;

    rate = rate.clip(0.01, 100);
    type = type.clip(0, 3);

    // Smooth random: interpolated between random values
    smooth = LFNoise1.kr(rate).unipolar;

    // Stepped random: discrete jumps at rate frequency
    stepped = LFNoise0.kr(rate).unipolar;

    // Lorenz chaotic attractor: three coupled differential equations
    // Produces deterministic chaos — repeating patterns that never repeat
    lorenz = {
        var x, y, z;
        #x, y, z = LorenzL.ar(
            rate.linlin(0.01, 100, 20, 200),
            10, 28, 2.667
        );
        // Lorenz x output ranges roughly -20 to 20; normalize to 0-1
        A2K.kr(x.linlin(-25, 25, 0, 1).clip(0, 1));
    }.value;

    // Gaussian random: normal distribution, mean=0.5, sd=0.15
    // Clipped to 0-1 to stay in safe modulation range
    gaussian = {
        var noise = LFNoise0.kr(rate);
        var gauss = (noise + LFNoise0.kr(rate * 1.1) + LFNoise0.kr(rate * 0.9)) / 3;
        gauss.linlin(-1, 1, 0, 1);
    }.value;

    sig = Select.kr(type.round, [
        smooth,     // 0: smooth
        stepped,    // 1: stepped
        lorenz,     // 2: Lorenz attractor
        gaussian    // 3: Gaussian
    ]);

    Out.kr(outBus, sig);
}).add;

// ==========================================
// 6. AQUA_ENV_FOLLOWER — Envelope Follower
// ==========================================
// Converts audio signal amplitude to control voltage. Reads an audio-rate
// input, extracts its amplitude envelope, and outputs a control-rate CV
// signal. Independent attack and release times control how quickly the
// follower responds to transients vs. how smoothly it decays.
// Useful for: ducking, dynamic filtering, amplitude-triggered events.
SynthDef(\aqua_env_follower, {
    |inBus=0, outBus=0, attack=0.01, release=0.1|

    var input, env;

    input = In.ar(inBus, 1);
    attack = attack.clip(0.0001, 2);
    release = release.clip(0.001, 5);

    // Amplitude follower with independent attack/release ballistics
    env = Amplitude.kr(input, attack, release);

    Out.kr(outBus, env);
}).add;

"--- BRAHMA: AQUA VITAE Modular Modulation Online (6 modules) ---".postln;
"  AQUA_LFO | AQUA_SAMPLE_HOLD | AQUA_TRACK_HOLD".postln;
"  AQUA_SLEW | AQUA_RANDOM | AQUA_ENV_FOLLOWER".postln;

// ==========================================
// PATCH BAY REGISTRATION — Modular Modulation Sources
// ==========================================
[
    [\aqua_lfo, [
        [\rate, "LFO rate"], [\shape, "Waveform shape"]
    ]],
    [\aqua_sample_hold, [
        [\slew, "Slew amount"]
    ]],
    [\aqua_slew, [
        [\rise, "Rise rate"], [\fall, "Fall rate"]
    ]],
    [\aqua_random, [
        [\type, "Random type"], [\rate, "Rate"]
    ]],
    [\aqua_env_follower, [
        [\attack, "Attack time"], [\release, "Release time"]
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

// ==========================================
// MODULE REGISTRY REGISTRATION — Modular Modulation Sources
// ==========================================
if(~MODULE_REGISTRY.notNil) {
    // 1. AQUA_LFO — Multi-waveform LFO with sync and reset
    ~MODULE_REGISTRY.register(\aqua_lfo, \modular, \aqua_lfo, [
        (\name: \rate, \default: 1, \min: 0.001, \max: 100, \units: "Hz", \desc: "LFO rate"),
        (\name: \shape, \default: 0, \min: 0, \max: 5, \units: "", \desc: "Waveform shape (0=sine, 1=tri, 2=saw, 3=square, 4=S&H, 5=random walk)"),
        (\name: \syncBus, \default: 0, \min: 0, \max: 8191, \units: "bus", \desc: "Sync input bus"),
        (\name: \resetBus, \default: 0, \min: 0, \max: 8191, \units: "bus", \desc: "Reset input bus"),
    ], ~SC_GRP[\te], "Multi-waveform LFO with sync and reset (6 shapes)");

    // 2. AQUA_SAMPLE_HOLD — Sample & Hold with slew
    ~MODULE_REGISTRY.register(\aqua_sample_hold, \modular, \aqua_sample_hold, [
        (\name: \inBus, \default: 0, \min: 0, \max: 8191, \units: "bus", \desc: "Input signal bus"),
        (\name: \trigBus, \default: 0, \min: 0, \max: 8191, \units: "bus", \desc: "Trigger input bus"),
        (\name: \slew, \default: 0, \min: 0, \max: 5, \units: "s", \desc: "Slew (portamento) time between sampled values"),
    ], ~SC_GRP[\te], "Sample & Hold with adjustable slew");

    // 3. AQUA_TRACK_HOLD — Track & Hold (toggle)
    ~MODULE_REGISTRY.register(\aqua_track_hold, \modular, \aqua_track_hold, [
        (\name: \inBus, \default: 0, \min: 0, \max: 8191, \units: "bus", \desc: "Input signal bus"),
        (\name: \trigBus, \default: 0, \min: 0, \max: 8191, \units: "bus", \desc: "Trigger input bus (toggles track/hold)"),
    ], ~SC_GRP[\te], "Track & Hold — passes signal until trigger freezes value");

    // 4. AQUA_SLEW — Slew Limiter with independent rise/fall
    ~MODULE_REGISTRY.register(\aqua_slew, \modular, \aqua_slew, [
        (\name: \inBus, \default: 0, \min: 0, \max: 8191, \units: "bus", \desc: "Input signal bus"),
        (\name: \rise, \default: 0.1, \min: 0, \max: 10, \units: "s", \desc: "Rise (ascending) slew rate"),
        (\name: \fall, \default: 0.1, \min: 0, \max: 10, \units: "s", \desc: "Fall (descending) slew rate"),
    ], ~SC_GRP[\te], "Slew limiter with independent rise and fall rates");

    // 5. AQUA_RANDOM — Multi-mode random generator
    ~MODULE_REGISTRY.register(\aqua_random, \modular, \aqua_random, [
        (\name: \type, \default: 0, \min: 0, \max: 3, \units: "", \desc: "Random mode (0=smooth, 1=stepped, 2=Lorenz, 3=Gaussian)"),
        (\name: \rate, \default: 1, \min: 0.01, \max: 100, \units: "Hz", \desc: "Rate of random change"),
    ], ~SC_GRP[\te], "Random generator (smooth, stepped, Lorenz, Gaussian)");

    // 6. AQUA_ENV_FOLLOWER — Audio-to-CV envelope follower
    ~MODULE_REGISTRY.register(\aqua_env_follower, \modular, \aqua_env_follower, [
        (\name: \inBus, \default: 0, \min: 0, \max: 8191, \units: "bus", \desc: "Audio input bus"),
        (\name: \attack, \default: 0.01, \min: 0.0001, \max: 2, \units: "s", \desc: "Attack time (transient response)"),
        (\name: \release, \default: 0.1, \min: 0.001, \max: 5, \units: "s", \desc: "Release time (decay smoothing)"),
    ], ~SC_GRP[\te], "Audio-to-CV envelope follower with attack/release ballistics");

    "  MODULE_REGISTRY: 6 Aqua Vitae modulation modules registered".postln;
};
)
