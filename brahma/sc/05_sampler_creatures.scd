/*
  Phase 5: The Anthropomorphic Sampler Creatures
*/

(
// ------------------------------------------------------------
// 1. MNEMOSYNE (The Archivist Eater)
// Long-term buffer with tape aging
// ------------------------------------------------------------
SynthDef(\mnemosyne_voice, {
    |outBus=0, buf, 
     age=0.0, erosion=0.0, recallOffset=0.0|
    
    var sig, rate, flutter, wow, dust;
    
    // Tape Mechanics
    wow = LFNoise2.kr(0.5).bipolar(age * 0.05);
    flutter = LFNoise1.kr(10).bipolar(age * 0.02);
    rate = 1.0 + wow + flutter;
    
    sig = PlayBuf.ar(1, buf, rate, loop: 1);
    
    // Erosion (High freq loss + saturation)
    sig = LPF.ar(sig, 18000 - (erosion * 15000));
    sig = tanh(sig * (1 + (age * 0.5)));
    
    // Dust/Crackle
    dust = Dust2.ar(age * 10) * 0.1;
    
    Out.ar(outBus, sig + dust);
}).add;

// ------------------------------------------------------------
// 2. PROTEAN HOUND (The Tracker of Fragments)
// Transient-driven re-triggering
// ------------------------------------------------------------
SynthDef(\protean_hound, {
    |inBus=0, outBus=0, buf,
     sensitivity=0.5, aggression=0.5, chaos=0.0|
    
    var in, trig, ptr, sig;
    
    in = In.ar(inBus, 1);
    trig = Onsets.kr(FFT(LocalBuf(512), in), sensitivity);
    
    // Record input continuously
    RecordBuf.ar(in, buf, loop: 1);
    
    // Playback logic: jump on transient
    // Aggression = shorter windows/more jumps
    // Chaos = random offset from write head
    ptr = Phasor.ar(0, 1, 0, BufFrames.ir(buf));
    
    // When trigger happens, jump read pointer
    // Jump back by random amount proportional to chaos
    ptr = TChoose.kr(trig, [
        ptr - (TRand.kr(0.01, 0.5, trig) * SampleRate.ir * chaos),
        ptr // or stay
    ]);
    
    sig = BufRd.ar(1, buf, ptr, loop: 1);
    
    Out.ar(outBus, sig);
}).add;

// ------------------------------------------------------------
// 3. CHRYSALID SIREN (The Metamorphic Vocalist)
// Granular morphing
// ------------------------------------------------------------
SynthDef(\chrysalid_siren, {
    |inBus=0, outBus=0, buf,
     grainDensity=10, identityBlur=0.0, formantShift=0.0|
    
    var trig, pos, sig, dur, pitchRatio;
    
    // Continuous recording
    RecordBuf.ar(In.ar(inBus, 1), buf, loop: 1);
    
    trig = Impulse.kr(grainDensity);
    pos = Phasor.ar(0, 1, 0, BufFrames.ir(buf)) / BufFrames.ir(buf);
    
    // Identity Blur = Position Jitter
    pos = pos + LFNoise1.kr(10).bipolar(identityBlur * 0.1);
    
    // Formant Shift = Pitch Ratio
    pitchRatio = 2 ** (formantShift / 12);
    
    dur = 1.2 / grainDensity;
    
    sig = GrainBuf.ar(2, trig, dur, buf, pitchRatio, pos, 2, pan: 0);
    
    Out.ar(outBus, sig);
}).add;

// ------------------------------------------------------------
// 4. OSSUARY MONK (The Percussive Relic)
// Resonator bank excited by input
// ------------------------------------------------------------
SynthDef(\ossuary_monk, {
    |inBus=0, outBus=0, 
     impactThreshold=0.5, relicDecay=1.0, gravity=0.0|
    
    var in, trig, exciter, sig;
    
    in = In.ar(inBus, 1);
    
    // Impulse detection
    trig = Coyote.kr(in, thresh: impactThreshold);
    exciter = Decay.ar(K2A.ar(trig), 0.01) * PinkNoise.ar;
    
    // Resonator (Bone/Wood/Metal tones)
    // Frequencies shift with "Gravity"
    sig = DynKlank.ar(
        `[[200, 450, 800, 1200] * (1 - (gravity * 0.5)), 
          [1, 0.8, 0.6, 0.4], 
          [1, 1, 1, 1] * relicDecay],
        exciter
    );
    
    Out.ar(outBus, sig);
}).add;

// ------------------------------------------------------------
// 5. JANIFORM CHILD (The Reversible Listener)
// Forward/Reverse duality
// ------------------------------------------------------------
SynthDef(\janiform_child, {
    |inBus=0, outBus=0, buf,
     symmetry=0.5, causalDrift=0.0|
    
    var fwd, rev, sig, ptr;
    
    RecordBuf.ar(In.ar(inBus, 1), buf, loop: 1);
    
    // Forward pointer
    ptr = Phasor.ar(0, 1, 0, BufFrames.ir(buf));
    fwd = BufRd.ar(1, buf, ptr, loop: 1);
    
    // Reverse pointer (mirrored)
    // Causal Drift adds offset to reverse head
    rev = BufRd.ar(1, buf, 
        (BufFrames.ir(buf) - ptr + (causalDrift * SampleRate.ir)).wrap(0, BufFrames.ir(buf)), 
        loop: 1
    );
    
    sig = XFade2.ar(fwd, rev, (symmetry * 2) - 1);
    
    Out.ar(outBus, sig);
}).add;

"--- BRAHMA: Anthropomorphic Creatures Loaded ---".postln;
)
