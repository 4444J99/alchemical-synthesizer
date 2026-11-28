/*
  Phase 15: The Golem Organism
  7-Stage Percussion Creature (follows Relinquished contract)

  IA → EG → BC → AE → TE → PR → RR
  Registered with AdamKadmon, FSAP-compliant absorption
*/

(
// ==========================================
// STAGE IA: Input Assimilation
// ==========================================
SynthDef(\golem_ia, {
    |inBusA=0, inBusB=1, outBus=0,
     iaSelect=0,           // 0=A (external audio), 1=B
     iaGain=1.0,           // 0..4
     iaPadDb=0.0,          // 0, -10, -20
     iaHpHz=20.0,          // 10..200
     iaLimit=1,            // 0/1
     iaClipBus=0|

    var a, b, sel, pad, gain, hp, limited, clip;

    a = In.ar(inBusA, 1);
    b = In.ar(inBusB, 1);

    sel = Select.ar(iaSelect.clip(0, 1), [a, b]);

    pad = sel * (10 ** (iaPadDb / 20));
    gain = pad * iaGain.clip(0, 4);
    hp = HPF.ar(gain, iaHpHz.clip(10, 200));

    limited = Select.ar(iaLimit.clip(0, 1), [
        hp,
        Limiter.ar(LeakDC.ar(hp), 0.98, 0.01)
    ]);

    clip = (Amplitude.kr(hp, 0.01, 0.05) > 0.98).lag(0.02);
    Out.kr(iaClipBus, clip);

    Out.ar(outBus, limited);
}).add;

// ==========================================
// STAGE BC: Binding Core (Multi-Buffer)
// ==========================================
// 8 track buffers for sample capture/playback with freeze/jitter/trim
SynthDef(\golem_bc, {
    |inBus=0, outBus=0,
     equipState=0,         // 0/1
     equipTrig=0,
     evictTrig=0,
     bcFreeze=0.0,         // 0..1
     bcLenMs=500.0,        // 5..2000 (longer for drum samples)
     bcReadPos=0.0,        // 0..1 (sample start)
     bcEndPos=1.0,         // 0..1 (sample end)
     bcPitch=1.0,          // 0.5..2 playback rate
     bcReverse=0,          // 0/1
     bcJitterMs=0.0,       // 0..50
     bcValidBus=0|

    var in, lenS, bufFrames, buf, writeOn, prime, valid;
    var startFrame, endFrame, readRate, ph, out;

    in = In.ar(inBus, 1);

    bufFrames = (2.0 * SampleRate.ir).asInteger.max(2); // 2 sec max
    buf = LocalBuf(bufFrames, 1);

    lenS = bcLenMs.clip(5, 2000) / 1000;
    writeOn = (equipState > 0) * (1 - bcFreeze.clip(0, 1));

    prime = Trig1.kr(equipTrig, lenS);
    valid = (Sweep.kr(equipTrig, 1) > lenS).lag(0.0);
    valid = valid * (1 - Trig1.kr(evictTrig, 0.05));
    Out.kr(bcValidBus, valid);

    // Write phase
    BufWr.ar(in, buf, Phasor.ar(writeOn, 1, 0, bufFrames), loop: 1);

    // Read phase with sample trim and pitch
    startFrame = bcReadPos.clip(0, 1) * bufFrames;
    endFrame = bcEndPos.clip(0, 1) * bufFrames;

    readRate = bcPitch.clip(0.25, 4);
    readRate = Select.kr(bcReverse.clip(0, 1), [readRate, readRate.neg]);

    ph = Phasor.ar(equipTrig, readRate, startFrame, endFrame, startFrame);

    // Jitter
    ph = ph + (TRand.ar(bcJitterMs.neg, bcJitterMs, equipTrig) * SampleRate.ir / 1000);
    ph = ph.clip(0, bufFrames - 1);

    out = BufRd.ar(1, buf, ph, loop: 1, interpolation: 4);

    Out.ar(outBus, out * valid);
}).add;

// ==========================================
// STAGE AE: Analysis Extraction
// ==========================================
SynthDef(\golem_ae, {
    |inBus=0,
     aeRateHz=50.0,
     aeSmoothMs=40.0,
     aeEnvSens=1.0,
     cvEnvBus=0, cvToneBus=1, cvNoiseBus=2, cvOnsetBus=3|

    var in, env, envSm;
    var chain, centroid, flat, tone01, noise01, onset;

    in = In.ar(inBus, 1);

    // Amplitude envelope
    env = Amplitude.kr(in, 0.01, 0.05) * aeEnvSens.clip(0.25, 4);
    envSm = Lag.kr(env, aeSmoothMs.clip(0, 500) / 1000);

    // FFT analysis
    chain = FFT(LocalBuf(1024), in);
    centroid = SpecCentroid.kr(chain);
    flat = SpecFlatness.kr(chain);

    tone01 = centroid.explin(50, 8000, 0, 1).clip(0, 1);
    noise01 = flat.clip(0, 1);

    // Onset detection
    onset = Onsets.kr(chain, 0.5);

    Out.kr(cvEnvBus, envSm.clip(0, 1));
    Out.kr(cvToneBus, tone01);
    Out.kr(cvNoiseBus, noise01);
    Out.kr(cvOnsetBus, onset);
}).add;

// ==========================================
// STAGE TE: Transmutation Engine (Multi-Source Mixer)
// ==========================================
// 4 sources: synthA, synthB, sampleA, sampleB with blend and cross-mod
SynthDef(\golem_te, {
    |inBusSynthA=0, inBusSynthB=1, inBusSampleA=2, inBusSampleB=3,
     outBus=0,
     blendA=1.0, blendB=0.0, blendSA=0.0, blendSB=0.0,
     xmodABpitch=0, xmodABfilter=0, xmodABamp=0,
     ringMod=0, driveAmt=0,
     cvEnvBus=0, cvToneBus=1|

    var sA, sB, smA, smB, mix, ring, driven, env, tone;

    sA = In.ar(inBusSynthA, 1);
    sB = In.ar(inBusSynthB, 1);
    smA = In.ar(inBusSampleA, 1);
    smB = In.ar(inBusSampleB, 1);

    env = In.kr(cvEnvBus, 1);
    tone = In.kr(cvToneBus, 1);

    // Cross-modulation: A modulates B's amplitude
    sB = sB * (1 + (sA * xmodABamp.clip(0, 1)));

    // Blend all 4 sources
    mix = (sA * blendA.clip(0, 1))
        + (sB * blendB.clip(0, 1))
        + (smA * blendSA.clip(0, 1))
        + (smB * blendSB.clip(0, 1));

    // Ring modulation
    ring = mix * SinOsc.ar(20 + (tone * 2000));
    mix = XFade2.ar(mix, ring, ringMod.clip(0, 1) * 2 - 1);

    // Drive (tanh saturation)
    driven = (mix * (1 + (driveAmt.clip(0, 1) * 9))).tanh;
    mix = XFade2.ar(mix, driven, driveAmt.clip(0, 1) * 2 - 1);

    Out.ar(outBus, LeakDC.ar(mix));
}).add;

// ==========================================
// STAGE PR: Protection/Reflection
// ==========================================
SynthDef(\golem_pr, {
    |inBus=0, outBus=0, reflectBus=0,
     iaClipBus=0,
     cvToneBus=1,
     prMode=0,             // 0=SACRIFICE, 1=INVERT, 2=RING, 3=MUTE
     prThrDbfs=(-12.0),
     prResponseMs=10.0,
     prReflectMix=0.30,
     prFbGain=0.10,
     prFaultBus=0|

    var in, sum, thrLin, iaClip, amp, overload, respS, overGate;
    var tone, inv, ring, reflect, out, fault, trig;

    in = In.ar(inBus, 1);

    iaClip = In.kr(iaClipBus, 1);
    tone = In.kr(cvToneBus, 1);
    thrLin = 10 ** (prThrDbfs.clip(-24, -3) / 20);

    amp = Amplitude.kr(in, 0.01, 0.05);
    overload = (amp > thrLin) + (iaClip > 0);
    respS = prResponseMs.clip(1, 100) / 1000;
    overGate = (Lag.kr(overload, respS) > 0).lag(0.0);

    // Reflection signals
    inv = in.neg * prReflectMix.clip(0, 1);
    ring = (in * SinOsc.ar(200 + (tone * 800))) * prReflectMix.clip(0, 1);
    reflect = Select.ar(prMode.clip(0, 3), [DC.ar(0), inv, ring, DC.ar(0)]);

    fault = Latch.kr(((prMode.clip(0, 3) - 3).abs < 0.5) * overGate, 1);
    Out.kr(prFaultBus, fault);

    trig = (prMode.clip(0, 3) < 0.5) * overGate;

    out = Select.ar(prMode.clip(0, 3), [
        (in * (1 - trig)).lag(0.01),           // SACRIFICE
        Limiter.ar(in, 0.98, 0.02),            // INVERT
        Limiter.ar(in, 0.98, 0.02),            // RING
        Select.ar(fault, [Limiter.ar(in, 0.98, 0.02), DC.ar(0)])  // MUTE
    ]);

    Out.ar(reflectBus, reflect);
    Out.ar(outBus, out);
}).add;

// ==========================================
// STAGE RR: Release Router
// ==========================================
SynthDef(\golem_rr, {
    |iaBus=0, prBus=1, outBus=0,
     rrBypass=0,           // 0=processed, 1=bypass (straight from IA)
     rrLevelDb=0.0,        // -99..+6
     rrPan=0.0|            // -1..+1

    var ia, pr, level, out;

    ia = In.ar(iaBus, 1);
    pr = In.ar(prBus, 1);
    level = 10 ** (rrLevelDb.clip(-99, 6) / 20);

    out = Select.ar(rrBypass.clip(0, 1), [pr, ia]) * level;

    // Pan to stereo for output
    Out.ar(outBus, Pan2.ar(out, rrPan.clip(-1, 1)));
}).add;

"--- BRAHMA: Golem 7-Stage SynthDefs Loaded ---".postln;

// ==========================================
// GOLEM LANGUAGE-SIDE CONTROLLER
// ==========================================
~golem = (
    entityId: 2001,
    type: "Golem",
    equipState: \idle,     // \idle, \equipped, \absorbing
    donorId: nil,
    donorTraits: nil,

    // ==========================================
    // REGISTRATION
    // ==========================================
    register: { |self|
        var traitMap = (
            spectral_profile: (
                centroid: 0.5,
                flatness: 0.6,
                bandwidth: 0.7,
                rolloff: 0.4
            ),
            temporal_topology: (
                attack: 0.01,
                decay: 0.3,
                sustain: 0.1,
                release: 0.15,
                slew: 0.9
            ),
            modulation_graph: (
                type: \percussive,
                sources: 24,    // 3 LFOs x 8 tracks
                dests: 15,
                routes: 0
            ),
            performance_response: (
                velocity: 0.8,
                aftertouch: 0.0,
                xy_sensitivity: 0.5,
                humanize: 0.1
            )
        );

        ~brahma_registry.registerEntity(self.entityId, self.type, traitMap);
        "GOLEM: Registered as entity % with AdamKadmon".format(self.entityId).postln;
    },

    // ==========================================
    // BUS ALLOCATION
    // ==========================================
    allocate: { |self|
        // Per-track audio buses (voice output + FX chain)
        ~golem_seq.tracks.do({ |track, i|
            track[\audioBus] = Bus.audio(s, 1);
            track[\fxBus] = Bus.audio(s, 1);
            ~sc_bus.put(("golem_audio_" ++ i).asSymbol, track[\audioBus]);
            ~sc_bus.put(("golem_fx_" ++ i).asSymbol, track[\fxBus]);
        });

        // Golem-specific control buses
        ~sc_bus.put(\golem_clip, Bus.control(s, 1));
        ~sc_bus.put(\golem_cv_env, Bus.control(s, 1));
        ~sc_bus.put(\golem_cv_tone, Bus.control(s, 1));
        ~sc_bus.put(\golem_cv_noise, Bus.control(s, 1));
        ~sc_bus.put(\golem_cv_onset, Bus.control(s, 1));
        ~sc_bus.put(\golem_fault, Bus.control(s, 1));
        ~sc_bus.put(\golem_ia_out, Bus.audio(s, 1));
        ~sc_bus.put(\golem_bc_out, Bus.audio(s, 1));
        ~sc_bus.put(\golem_te_out, Bus.audio(s, 1));
        ~sc_bus.put(\golem_pr_out, Bus.audio(s, 1));
        ~sc_bus.put(\golem_reflect, Bus.audio(s, 1));

        "GOLEM: Buses allocated (% audio, % control)".format(
            ~golem_seq.tracks.size * 2 + 5, 6
        ).postln;
    },

    // ==========================================
    // FX CHAIN SETUP (per track)
    // ==========================================
    setupFXChain: { |self, trackIdx|
        var track = ~golem_seq.tracks[trackIdx];
        var bus = track[\audioBus];

        if(bus.notNil) {
            // Chain: voice (already outputs to audioBus) -> drive -> bitcrush -> delay -> reverb
            track[\fxSynths] = [
                Synth.after(~sc_grp[\te], \golem_drive, [
                    \inBus, bus.index, \outBus, bus.index,
                    \amount, track[\fx][\drive], \mix, (track[\fx][\drive] > 0).asInteger
                ]),
                Synth.after(~sc_grp[\te], \golem_bitcrush, [
                    \inBus, bus.index, \outBus, bus.index,
                    \amount, track[\fx][\bitcrush], \mix, (track[\fx][\bitcrush] > 0).asInteger
                ]),
                Synth.after(~sc_grp[\te], \golem_delay, [
                    \inBus, bus.index, \outBus, bus.index,
                    \time, track[\fx][\delayTime], \feedback, track[\fx][\delayFB],
                    \mix, track[\fx][\delayMix]
                ]),
                Synth.after(~sc_grp[\te], \golem_reverb, [
                    \inBus, bus.index, \outBus, bus.index,
                    \decay, track[\fx][\reverbDecay], \mix, track[\fx][\reverbMix]
                ])
            ];
        };
    },

    // ==========================================
    // FSAP-COMPLIANT ABSORPTION
    // ==========================================
    absorb: { |self, donorId|
        var traits;
        // Single-equip invariant: reject if already equipped
        if(self.equipState != \idle) {
            "GOLEM: Cannot absorb — currently in state '%'".format(self.equipState).warn;
            ^false;
        };

        traits = ~brahma_registry.getTraits(donorId);
        if(traits.isNil) {
            "GOLEM: Donor entity % not found in registry".format(donorId).warn;
            ^false;
        };

        self.equipState = \absorbing;
        self.donorId = donorId;
        self.donorTraits = traits;

        // Map donor spectral profile to drum voice params
        // Spectral centroid -> base frequency range
        // Flatness -> noise vs tone balance
        // Temporal topology -> envelope shape
        if(traits[\spectral_profile].notNil) {
            var centroid = traits[\spectral_profile][\centroid] ? 0.5;
            var flatness = traits[\spectral_profile][\flatness] ? 0.5;
            var attack = traits[\temporal_topology][\attack] ? 0.01;
            var decay = traits[\temporal_topology][\decay] ? 0.3;

            ~golem_seq.tracks.do({ |track|
                // Shift frequencies based on donor centroid
                track[\synthArgs][\freq] = (track[\synthArgs][\freq] ? 150) *
                    centroid.linexp(0, 1, 0.5, 2.0);
                // Mix in noise based on flatness
                if(track[\synthArgs][\noiseAmt].notNil) {
                    track[\synthArgs][\noiseAmt] = flatness.clip(0, 1);
                };
                // Shape envelopes
                track[\synthArgs][\atk] = attack.clip(0.001, 0.5);
                track[\synthArgs][\dec] = decay.clip(0.01, 2.0);
            });
        };

        self.equipState = \equipped;
        "GOLEM: Absorbed traits from entity %".format(donorId).postln;
        ^true;
    },

    evict: { |self|
        if(self.equipState == \idle) {
            "GOLEM: Nothing to evict".warn;
            ^false;
        };

        self.equipState = \idle;
        self.donorId = nil;
        self.donorTraits = nil;

        // Reset to factory defaults
        ~golem_seq.tracks.do({ |track, i|
            var presetNames = [\kick808, \snare, \clap, \hihatClosed,
                               \hihatOpen, \tom, \rim, \fmBell];
            var preset = ~golem_patterns.factory[presetNames[i]];
            if(preset.notNil) {
                track[\synthDef] = preset[\synthDef];
                track[\synthArgs] = preset[\args].copy;
            };
            // A slice binding does not survive evict: the track goes
            // back to its drum preset, so clear the chop, its source
            // tempo, and the playback rate with it (plan step 4), and
            // the transform fields with them (plan step 5) — a drum
            // track must not keep a stretch it never plays.
            track[\sliceTrack] = false;
            track[\sliceIndex] = 0;
            track[\sourceTempo] = nil;
            track[\rate] = 1.0;
            track[\transform] = \none;
            track[\stretchRate] = nil;
            track[\stretchPitch] = 1.0;
            track[\stretchGrain] = 0.1;
        });

        "GOLEM: Donor traits evicted, factory defaults restored".postln;
        ^true;
    },

    // ==========================================
    // BOOT SEQUENCE
    // ==========================================
    boot: { |self|
        // 1. Register with AdamKadmon
        self.register;

        // 2. Allocate buses
        self.allocate;

        // 3. Load factory presets to tracks
        [
            \kick808, \snare, \clap, \hihatClosed,
            \hihatOpen, \tom, \rim, \fmBell
        ].do({ |presetName, i|
            var preset = ~golem_patterns.factory[presetName];
            if(preset.notNil) {
                ~golem_seq.tracks[i][\synthDef] = preset[\synthDef];
                ~golem_seq.tracks[i][\synthArgs] = preset[\args].copy;
                ~golem_seq.tracks[i][\name] = presetName.asString;
            };
        });

        // 4. Set up FX chains for all tracks
        8.do({ |i| self.setupFXChain(i) });

        // 5. Start LFOs
        ~golem_seq.startLFOs;

        // 6. Init OSC responders
        ~golem_seq.initOSC;

        // 7. Set up a default 4-on-floor kick pattern
        [0, 4, 8, 12].do({ |step|
            ~golem_seq.tracks[0][\pattern][step][\active] = true;
        });
        // HH on 8ths
        8.do({ |i|
            ~golem_seq.tracks[3][\pattern][i * 2][\active] = true;
        });
        // Snare on 2 and 4
        [4, 12].do({ |step|
            ~golem_seq.tracks[1][\pattern][step][\active] = true;
        });

        "--- BRAHMA: Golem Organism Booted ---".postln;
    },

    // ==========================================
    // SHUTDOWN
    // ==========================================
    shutdown: { |self|
        ~golem_seq.stop;
        ~golem_seq.stopLFOs;

        // Free FX synths
        ~golem_seq.tracks.do({ |track|
            if(track[\fxSynths].notNil) {
                track[\fxSynths].do({ |syn| syn.free });
                track[\fxSynths] = nil;
            };
        });

        // Free buses
        ~golem_seq.tracks.do({ |track|
            if(track[\audioBus].notNil) { track[\audioBus].free; track[\audioBus] = nil };
            if(track[\fxBus].notNil) { track[\fxBus].free; track[\fxBus] = nil };
        });

        "--- BRAHMA: Golem Organism Shutdown ---".postln;
    }
);

// Boot Golem on load
~golem.boot;
)
