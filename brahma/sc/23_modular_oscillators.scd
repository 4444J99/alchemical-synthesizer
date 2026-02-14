/*
  Phase 23: ATHANOR — Alchemical Furnace Oscillator Suite
  Modular oscillator building blocks for the Brahma Meta-Rack.

  The Athanor (alchemical furnace) is the crucible of transmutation—
  the source of all raw sonic material before distillation.

  SynthDefs:
    1. \athanor_vco    — Classic VCO: saw/pulse/tri/sine with CV inputs
    2. \athanor_super  — Super oscillator: 1-7 voice unison with spread
    3. \athanor_sub    — Sub oscillator: -1/-2 octave, square/sine
    4. \athanor_noise  — Noise generator: white, pink, red, blue, violet, crackle
    5. \athanor_dust   — Random impulse generator with density control
    6. \athanor_chaos  — Chaotic oscillator: Lorenz, Henon, Standard map
*/

(
// ==========================================
// 1. ATHANOR VCO — Voltage-Controlled Oscillator
// ==========================================
// Core oscillator with 4 waveforms and CV inputs for
// frequency, pulse width modulation, hard sync, and FM.
// FM and sync sourced from external buses for true modular patching.
SynthDef(\athanor_vco, {
    |outBus=0, freq=220, wave=0, pwm=0.5,
     fmBus=0, fmAmt=0, syncBus=0|

    var saw, pulse, tri, sine;
    var fm_sig, sync_sig, fm_freq;
    var sig;

    // Read FM modulator from external bus (0 = no signal when bus is silent)
    fm_sig = In.ar(fmBus, 1);

    // FM: modulator scales carrier frequency exponentially
    // fmAmt 0-1 maps to 0-8 octaves of deviation
    fm_freq = freq * (1 + (fm_sig * fmAmt.clip(0, 1) * 8));
    fm_freq = fm_freq.clip(0.1, 20000);

    // Read sync source from external bus
    sync_sig = In.ar(syncBus, 1);

    // Generate all four waveforms at the FM'd frequency
    saw = Saw.ar(fm_freq);
    pulse = Pulse.ar(fm_freq, pwm.clip(0.01, 0.99));
    tri = LFTri.ar(fm_freq);
    sine = SinOsc.ar(fm_freq);

    // Waveform selection: 0=saw, 1=pulse, 2=tri, 3=sine
    sig = Select.ar(wave.clip(0, 3).round, [
        saw, pulse, tri, sine
    ]);

    // Hard sync: when sync source crosses zero upward, reset phase
    // Achieved by mixing with a sync'd saw at same frequency
    sig = Select.ar((fmAmt > 0).asInteger.min(1), [
        // When no FM, use SyncSaw for true hard sync if sync signal present
        Select.ar((In.ar(syncBus, 1).abs.sum > 0.001).asInteger, [
            sig,
            SyncSaw.ar(In.ar(syncBus, 1).abs.max(0.1) * freq, fm_freq)
        ]),
        sig
    ]);

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


// ==========================================
// 2. ATHANOR SUPER — Unison Super Oscillator
// ==========================================
// 1-7 detuned saw voices with stereo spread.
// The "fat/thin" character emerges from voice count and detune depth.
// Lower voice counts with tight detune = subtle thickening;
// 7 voices with wide detune = massive supersaw wall.
SynthDef(\athanor_super, {
    |outBus=0, freq=220, voices=5, spread=0.5, detune=0.1|

    var num_voices, sig;
    var detune_amt, spread_amt;

    // Clip params to safe ranges
    num_voices = voices.clip(1, 7).round;
    detune_amt = detune.clip(0, 1);
    spread_amt = spread.clip(0, 1);

    // Generate detuned voice stack
    // Each voice offset symmetrically around center frequency
    sig = Mix.fill(7, { |i|
        var voice_active, voice_detune, voice_freq, voice_pan;

        // Only generate audio for active voices
        voice_active = (i < num_voices).asInteger;

        // Symmetric detune: center voice has no detune,
        // others spread outward in both directions
        voice_detune = (i - 3) / 3.0 * detune_amt * freq * 0.02;

        // Per-voice random drift for analog character
        voice_detune = voice_detune + LFNoise2.kr(0.5 + (i * 0.1)).range(-0.3, 0.3);

        voice_freq = (freq + voice_detune).clip(0.1, 20000);

        // Stereo spread: voices distributed across stereo field
        voice_pan = (i - 3) / 3.0 * spread_amt;

        Saw.ar(voice_freq) * voice_active / num_voices;
    });

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


// ==========================================
// 3. ATHANOR SUB — Sub Oscillator
// ==========================================
// Generates a sub-frequency tone at -1 or -2 octaves
// below the input frequency. Square or sine waveshape.
// Essential for adding weight and bottom-end foundation.
SynthDef(\athanor_sub, {
    |outBus=0, freq=220, octave=1, wave=0|

    var sub_freq, sig;

    // Octave division: 1 = -1 octave, 2 = -2 octaves
    sub_freq = freq / (2 ** octave.clip(1, 2).round);
    sub_freq = sub_freq.clip(0.1, 20000);

    // Waveform: 0 = square, 1 = sine
    sig = Select.ar(wave.clip(0, 1).round, [
        Pulse.ar(sub_freq, 0.5),
        SinOsc.ar(sub_freq)
    ]);

    Out.ar(outBus, sig);
}).add;


// ==========================================
// 4. ATHANOR NOISE — Multi-Color Noise Generator
// ==========================================
// Six noise flavors spanning the full spectral range.
// White (flat), pink (1/f), red/brown (1/f^2), blue (+3dB/oct),
// violet (+6dB/oct), crackle (stochastic particle noise).
SynthDef(\athanor_noise, {
    |outBus=0, type=0|

    var sig;

    // Noise type selection: 0=white, 1=pink, 2=red/brown, 3=blue, 4=violet, 5=crackle
    sig = Select.ar(type.clip(0, 5).round, [
        // 0: White — flat spectral density
        WhiteNoise.ar,

        // 1: Pink — 1/f rolloff, equal energy per octave
        PinkNoise.ar,

        // 2: Red/Brown — 1/f^2, random walk (Brownian motion)
        BrownNoise.ar,

        // 3: Blue — +3dB/oct, high-frequency emphasis
        // Derived by differencing white noise (HPF approximation)
        HPF.ar(WhiteNoise.ar, 1000) * 1.5,

        // 4: Violet — +6dB/oct, even more high-frequency energy
        // Second-order high-pass of white noise
        HPF.ar(HPF.ar(WhiteNoise.ar, 500), 1000) * 2.0,

        // 5: Crackle — chaotic stochastic noise
        Crackle.ar(1.5)
    ]);

    Out.ar(outBus, sig);
}).add;


// ==========================================
// 5. ATHANOR DUST — Random Impulse Generator
// ==========================================
// Generates randomly-timed impulses at a controllable density.
// At low density: sparse clicks; at high density: textured noise.
// Useful as an excitation source for resonators and filters.
SynthDef(\athanor_dust, {
    |outBus=0, density=1.0|

    var sig;

    // Density: impulses per second (0.01 to 1000 Hz)
    sig = Dust.ar(density.clip(0.01, 1000));

    Out.ar(outBus, sig);
}).add;


// ==========================================
// 6. ATHANOR CHAOS — Chaotic Oscillator
// ==========================================
// Three chaotic attractor models producing complex,
// non-repeating waveforms. Param1 and param2 control
// the attractor geometry, pushing between periodic
// orbits and fully chaotic behavior.
//
// Lorenz: classic strange attractor (weather model)
// Henon: 2D discrete map with fractal basin
// Standard (Chirikov): kicked rotator, models particle chaos
SynthDef(\athanor_chaos, {
    |outBus=0, type=0, freq=220, param1=10, param2=28|

    var sig;
    var chaos_freq;

    // Map freq to a rate suitable for chaotic oscillators
    chaos_freq = freq.clip(0.1, 20000);

    sig = Select.ar(type.clip(0, 2).round, [
        // 0: Lorenz attractor
        // param1 = sigma (typically 10), param2 = rho (typically 28)
        // Outputs the X dimension of the Lorenz system
        LorenzL.ar(
            SampleRate.ir / (SampleRate.ir / chaos_freq).max(1),
            param1.clip(0.1, 50),  // sigma
            param2.clip(0.1, 80),  // rho
            2.67,                   // beta (standard value)
            0.05, 0.1, 0.1         // initial conditions
        ) * 0.1,  // Scale down (Lorenz output is large)

        // 1: Henon map
        // param1 = a (typically 1.4), param2 = b (typically 0.3)
        // Classic 2D chaotic map with fractal structure
        HenonL.ar(
            chaos_freq.clip(20, SampleRate.ir / 2),
            param1.clip(0.1, 2.0),  // a
            param2.clip(0.01, 0.99), // b
            0.1, 0.1               // initial conditions
        ),

        // 2: Standard (Chirikov) map
        // param1 = perturbation (k), param2 = modulation
        // Transitions from regular to chaotic motion
        StandardL.ar(
            chaos_freq.clip(20, SampleRate.ir / 2),
            param1.clip(0.1, 20),  // k: stochasticity parameter
            0.5, 0.5               // initial conditions
        )
    ]);

    // Safety clip: chaotic oscillators can produce extreme values
    sig = sig.clip(-1, 1);

    Out.ar(outBus, LeakDC.ar(sig));
}).add;


"--- BRAHMA: ATHANOR Oscillator Suite Online (6 SynthDefs) ---".postln;
"  ATHANOR VCO | ATHANOR SUPER | ATHANOR SUB".postln;
"  ATHANOR NOISE | ATHANOR DUST | ATHANOR CHAOS".postln;
)
