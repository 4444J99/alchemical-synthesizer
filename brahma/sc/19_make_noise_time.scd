/*
  Phase 19: Make Noise Time-Domain Processor Clones
  5 SynthDefs emulating Make Noise's temporal manipulation modules:
    1. CHRONOS ECHO   (Mimeophon)  — Micro-looping audio repeater
    2. CHRONOS PITCH  (Echophon)   — Pitch-shifting echo
    3. MORPHEUS TAPE  (Morphagene) — Microsound tape machine
    4. MORPHEUS PHONO (Phonogene)  — Granular sampler/looper
    5. SPATIAL ERBE   (Erbe-Verb)  — DSP reverb

  All SynthDefs follow standard Brahma interface:
    outBus, inBus (snake_case), modular routing via In/Out
*/

(
// ============================================================
// 1. CHRONOS ECHO — Mimeophon Clone
//    Micro-looping audio repeater with three behavior zones:
//      0=karplus, 1=delay, 2=reverb-like
//    Mono input → stereo output with micro-detuned repeats
// ============================================================
SynthDef(\chronos_echo, {
    |inBus=0, outBus=0,
     rate=0.25, color=0.5, zone=1, halo=0.5, hold=0, mix=0.5|

    var in, buf, buf_frames, write_phase, read_phase;
    var delay_time, feedback, fb_sig, delayed_l, delayed_r;
    var color_freq, filtered, held, sig, dry;
    var zone_sel, karplus, tape_delay, reverb_wash;
    var micro_detune, halo_sat;

    in = In.ar(inBus, 1);
    dry = in;

    // Buffer for micro-looping (2 seconds max at sample rate)
    buf_frames = (2.0 * SampleRate.ir).asInteger.max(2);
    buf = LocalBuf(buf_frames, 1);

    // Rate controls repeat time: 0.01 to 2.0 seconds
    delay_time = rate.clip(0.01, 2.0);

    // Feedback with soft-clip saturation
    halo_sat = halo.clip(0, 0.98);
    fb_sig = LocalIn.ar(1) * halo_sat;
    fb_sig = (fb_sig * (1 + (halo_sat * 2))).tanh; // Saturated feedback

    // Write to buffer (freeze when hold is engaged)
    write_phase = Phasor.ar(0, 1 - hold.clip(0, 1), 0, buf_frames);
    BufWr.ar(in + fb_sig, buf, write_phase, loop: 1);

    // Read from buffer at delay offset
    read_phase = (write_phase - (delay_time * SampleRate.ir)).wrap(0, buf_frames);

    // Color: tonal character via crossfaded LP/HP filter in feedback path
    // color 0.0 = dark (low-pass), 1.0 = bright (high-pass)
    color_freq = color.linexp(0, 1, 200, 12000);

    // === ZONE 0: Karplus-Strong (resonant pluck) ===
    karplus = BufRd.ar(1, buf, read_phase, loop: 1, interpolation: 4);
    karplus = LPF.ar(karplus, (1 / delay_time.max(0.001)).clip(20, 20000) * 2);
    karplus = karplus * EnvGen.ar(Env.perc(0.001, delay_time * 4), Impulse.kr(1 / delay_time.max(0.01)));

    // === ZONE 1: Standard delay ===
    tape_delay = BufRd.ar(1, buf, read_phase, loop: 1, interpolation: 4);

    // === ZONE 2: Reverb-like (smeared, diffused) ===
    reverb_wash = BufRd.ar(1, buf, read_phase, loop: 1, interpolation: 4);
    // Allpass diffusion chain to smear the repeats
    reverb_wash = AllpassC.ar(reverb_wash, 0.05, 0.037, 0.5);
    reverb_wash = AllpassC.ar(reverb_wash, 0.05, 0.023, 0.7);
    reverb_wash = AllpassC.ar(reverb_wash, 0.05, 0.013, 0.9);
    reverb_wash = AllpassC.ar(reverb_wash, 0.05, 0.041, 0.6);

    // Zone selection
    zone_sel = Select.ar(zone.clip(0, 2).round, [karplus, tape_delay, reverb_wash]);

    // Apply color filter to the zone output
    filtered = SelectX.ar(color.clip(0, 1) * 2, [
        LPF.ar(zone_sel, color_freq),           // Dark
        zone_sel,                                // Neutral
        HPF.ar(zone_sel, color_freq * 0.5)       // Bright
    ]);

    // Feed back into the loop
    LocalOut.ar(filtered);

    // Hold: freeze buffer content (bypass write, keep reading)
    held = Select.ar(hold.clip(0, 1).round, [filtered, BufRd.ar(1, buf, read_phase, loop: 1, interpolation: 4)]);

    // Stereo output with micro-detuned repeats
    micro_detune = LFNoise1.kr(0.3).bipolar(0.002);
    delayed_l = held;
    delayed_r = DelayC.ar(held, 0.01, 0.003 + micro_detune.abs);

    // Dry/wet mix
    sig = XFade2.ar(dry ! 2, [delayed_l, delayed_r], mix.clip(0, 1) * 2 - 1);

    Out.ar(outBus, sig);
}).add;

// ============================================================
// 2. CHRONOS PITCH — Echophon Clone
//    Pitch-shifting echo with shimmer feedback
//    Each repeat is pitch-shifted, creating cascading harmonics
// ============================================================
SynthDef(\chronos_pitch, {
    |inBus=0, outBus=0,
     pitch=0, time=0.3, feedback=0.5, freeze=0, mix=0.5|

    var in, dry, delayed, shifted, fb_sig, sig;
    var pitch_ratio, delay_time, fb_amt;
    var buf, buf_frames, write_phase, read_phase;

    in = In.ar(inBus, 1);
    dry = in;

    // Pitch: -12 to +12 semitones
    pitch_ratio = 2 ** (pitch.clip(-12, 12) / 12);

    // Time: echo delay
    delay_time = time.clip(0.01, 2.0);

    // Feedback amount (clamped for stability)
    fb_amt = feedback.clip(0, 0.95);

    // Feedback path with pitch shifting
    fb_sig = LocalIn.ar(1) * fb_amt;

    // Delay line
    delayed = DelayC.ar(in + fb_sig, 2.0, delay_time);

    // Pitch shift the delayed signal
    // PitchShift with window size proportional to delay for musicality
    shifted = PitchShift.ar(
        delayed,
        windowSize: 0.2,
        pitchRatio: pitch_ratio,
        pitchDispersion: 0.01,
        timeDispersion: 0.004
    );

    // Freeze: infinite hold (set feedback to 1, mute input)
    shifted = Select.ar(freeze.clip(0, 1).round, [
        shifted,
        PitchShift.ar(
            DelayC.ar(fb_sig, 2.0, delay_time),
            windowSize: 0.2,
            pitchRatio: pitch_ratio,
            pitchDispersion: 0.002,
            timeDispersion: 0.002
        )
    ]);

    // Soft-clip to tame shimmer buildup
    shifted = shifted.tanh;

    // Feed back
    LocalOut.ar(Select.ar(freeze.clip(0, 1).round, [
        shifted,
        shifted * 0.99 // Near-infinite feedback when frozen
    ]));

    // Dry/wet mix
    sig = XFade2.ar(dry, shifted, mix.clip(0, 1) * 2 - 1);

    Out.ar(outBus, sig);
}).add;

// ============================================================
// 3. MORPHEUS TAPE — Morphagene Clone
//    Microsound tape machine with reel, gene (speed), organize
//    (scan position), splice/morph (crossfade between points),
//    and record toggle
// ============================================================
SynthDef(\morpheus_tape, {
    |inBus=0, outBus=0, bufnum=0,
     gene=1.0, slide=0.1, organize=0.0, morph=0.0, record=0, mix=0.5|

    var in, dry, sig, play_rate, smoothed_rate;
    var rec_phase, play_phase, play_sig;
    var buf_frames, organize_offset, splice_a, splice_b;
    var morph_xfade, window;

    in = In.ar(inBus, 1);
    dry = in;

    buf_frames = BufFrames.ir(bufnum);

    // Gene: playback speed/direction (-4x to +4x)
    play_rate = gene.clip(-4, 4);

    // Slide: smoothness of speed transitions (lag time in seconds)
    smoothed_rate = Lag.kr(play_rate, slide.clip(0.001, 2.0));

    // Record: write input to buffer when engaged
    rec_phase = Phasor.ar(0, BufRateScale.ir(bufnum), 0, buf_frames);
    BufWr.ar(in * record.clip(0, 1), bufnum, rec_phase, loop: 1);

    // Organize: scan position through the reel (0.0 = start, 1.0 = end)
    organize_offset = organize.clip(0, 1) * buf_frames;

    // Playback phase with variable speed
    play_phase = Phasor.ar(
        0,
        BufRateScale.ir(bufnum) * smoothed_rate,
        0,
        buf_frames
    );

    // Offset the play phase by organize position
    play_phase = (play_phase + organize_offset).wrap(0, buf_frames);

    // Morph: crossfade between current position and a position
    // displaced by half the buffer (simulating splice point navigation)
    splice_a = BufRd.ar(1, bufnum, play_phase, loop: 1, interpolation: 4);
    splice_b = BufRd.ar(1, bufnum,
        (play_phase + (buf_frames * 0.5)).wrap(0, buf_frames),
        loop: 1, interpolation: 4
    );

    // Morph crossfade between splice points
    morph_xfade = XFade2.ar(splice_a, splice_b, morph.clip(0, 1) * 2 - 1);

    // Gentle windowing to reduce clicks at splice boundaries
    window = Lag.ar(K2A.ar(1), 0.005);
    play_sig = morph_xfade * window;

    // When recording, mute playback to avoid feedback
    play_sig = play_sig * (1 - record.clip(0, 1));

    // Dry/wet mix
    sig = XFade2.ar(dry, play_sig, mix.clip(0, 1) * 2 - 1);

    Out.ar(outBus, LeakDC.ar(sig));
}).add;

// ============================================================
// 4. MORPHEUS PHONO — Phonogene Clone
//    Granular sampler/looper with splice-based segment playback
//    Variable grain density, size, pitch, and micro-sound control
// ============================================================
SynthDef(\morpheus_phono, {
    |inBus=0, outBus=0, bufnum=0,
     grainDensity=10, grainSize=0.05, pitch=0, splice=0.0, mix=0.5|

    var in, dry, sig, trig, pos, pitch_ratio;
    var buf_frames, splice_pos, grain_dur;
    var rec_phase;

    in = In.ar(inBus, 1);
    dry = in;

    buf_frames = BufFrames.ir(bufnum);

    // Continuous recording into buffer
    rec_phase = Phasor.ar(0, BufRateScale.ir(bufnum), 0, buf_frames);
    BufWr.ar(in, bufnum, rec_phase, loop: 1);

    // Grain trigger at specified density (1 to 100 Hz)
    trig = Impulse.kr(grainDensity.clip(1, 100));

    // Splice: divide buffer into segments, select segment start position
    // splice 0.0 = beginning, 1.0 = end of buffer
    splice_pos = splice.clip(0, 1);

    // Playback position: scan within the selected splice region
    // with slight jitter for micro-sound variation
    pos = splice_pos + LFNoise1.kr(grainDensity * 0.5).range(0, 0.1);
    pos = pos.clip(0, 0.999);

    // Grain duration from grainSize (0.001 to 0.5 seconds)
    grain_dur = grainSize.clip(0.001, 0.5);

    // Pitch: semitone shift mapped to ratio
    pitch_ratio = 2 ** (pitch.clip(-24, 24) / 12);

    // Granular playback
    sig = GrainBuf.ar(
        numChannels: 1,
        trigger: trig,
        dur: grain_dur,
        sndbuf: bufnum,
        rate: pitch_ratio * BufRateScale.ir(bufnum),
        pos: pos,
        interp: 4,
        pan: 0
    );

    // Dry/wet mix
    sig = XFade2.ar(dry, sig, mix.clip(0, 1) * 2 - 1);

    Out.ar(outBus, LeakDC.ar(sig));
}).add;

// ============================================================
// 5. SPATIAL ERBE — Erbe-Verb Clone
//    DSP reverb with absorb (damping), decay, speed (pitch-shift
//    tail), tilt (spectral tilt), size, and pre-delay
// ============================================================
SynthDef(\spatial_erbe, {
    |inBus=0, outBus=0,
     absorb=0.5, decay=2.0, speed=1.0, tilt=0.0, size=0.5, preDelay=0.0, mix=0.5|

    var in, dry, sig, pre_delayed;
    var decay_time, damp_freq, room_scale;
    var ap1, ap2, ap3, ap4, ap5, ap6;
    var comb1, comb2, comb3, comb4;
    var fb_matrix, early, late, tilted;
    var speed_ratio, pitched;
    var delay_times, fb_coeff;

    in = In.ar(inBus, 1);
    dry = in;

    // Pre-delay: 0 to 500ms
    pre_delayed = DelayC.ar(in, 0.5, (preDelay.clip(0, 500) / 1000));

    // Decay time: 0.1 to 100 seconds (100 = near-infinite)
    decay_time = decay.clip(0.1, 100);

    // Absorb: high-frequency damping (0 = bright, 1 = very dark)
    damp_freq = absorb.linexp(0, 1, 16000, 800);

    // Size: scales all delay line lengths (0.1 = tiny, 1.0 = huge)
    room_scale = size.linlin(0, 1, 0.3, 1.5);

    // Feedback coefficient derived from decay time
    // Higher decay = more feedback
    fb_coeff = (-3 * (0.035 * room_scale) / decay_time.max(0.1)).dbamp.clip(0, 0.999);

    // === Early reflections (4 allpass diffusers) ===
    early = pre_delayed;
    early = AllpassC.ar(early, 0.1, 0.0051 * room_scale, 0.02 * decay_time.min(5));
    early = AllpassC.ar(early, 0.1, 0.0073 * room_scale, 0.03 * decay_time.min(5));
    early = AllpassC.ar(early, 0.1, 0.011  * room_scale, 0.04 * decay_time.min(5));
    early = AllpassC.ar(early, 0.1, 0.017  * room_scale, 0.05 * decay_time.min(5));

    // === Late reverb tail (parallel comb filters + allpass diffusion) ===
    // Feedback network with damping
    fb_matrix = LocalIn.ar(1) * fb_coeff;
    fb_matrix = LPF.ar(fb_matrix, damp_freq); // Absorb = HF damping

    // Parallel comb filters with prime-ratio delay times for density
    comb1 = CombC.ar(early + fb_matrix, 0.2, 0.02971 * room_scale, decay_time);
    comb2 = CombC.ar(early + fb_matrix, 0.2, 0.03717 * room_scale, decay_time * 0.95);
    comb3 = CombC.ar(early + fb_matrix, 0.2, 0.04133 * room_scale, decay_time * 0.9);
    comb4 = CombC.ar(early + fb_matrix, 0.2, 0.04891 * room_scale, decay_time * 0.85);

    late = (comb1 + comb2 + comb3 + comb4) * 0.25;

    // Post-comb allpass diffusion for smoothness
    late = AllpassC.ar(late, 0.1, 0.0053 * room_scale, 0.1);
    late = AllpassC.ar(late, 0.1, 0.0079 * room_scale, 0.15);

    // Apply absorb damping to the entire tail
    late = LPF.ar(late, damp_freq);

    // Feed back into the comb network
    LocalOut.ar(late);

    // === Speed: pitch-shift the reverb tail ===
    // speed 1.0 = normal, <1 = down (droning), >1 = up (shimmering)
    speed_ratio = speed.clip(0.25, 4.0);
    pitched = Select.ar((speed_ratio - 1.0).abs > 0.01, [
        late,
        PitchShift.ar(late, 0.15, speed_ratio, 0.01, 0.01)
    ]);

    // === Tilt: spectral balance (dark ↔ bright) ===
    // tilt -1.0 = dark emphasis, 0.0 = neutral, 1.0 = bright emphasis
    tilted = SelectX.ar(tilt.linlin(-1, 1, 0, 2), [
        LPF.ar(pitched, 1500),       // Dark
        pitched,                      // Neutral
        HPF.ar(pitched, 300) + (pitched * 0.3) // Bright with body
    ]);

    // Combine early + late
    sig = (early * 0.3) + (tilted * 0.7);

    // Dry/wet mix
    sig = XFade2.ar(dry, LeakDC.ar(sig), mix.clip(0, 1) * 2 - 1);

    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: Make Noise Time-Domain Processors Loaded (5 modules) ---".postln;
"  CHRONOS ECHO (Mimeophon) | CHRONOS PITCH (Echophon)".postln;
"  MORPHEUS TAPE (Morphagene) | MORPHEUS PHONO (Phonogene)".postln;
"  SPATIAL ERBE (Erbe-Verb)".postln;
)
