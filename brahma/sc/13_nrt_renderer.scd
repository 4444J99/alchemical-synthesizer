/*
  Phase 13: Non-Real-Time (NRT) Rendering — Specimen / Track Bounce

  The headless spine: fed a WAV ("the food"), Brahma re-expresses it and writes
  a new WAV ("the result") with NO audio device and NO GUI — via scsynth -N
  (Score.recordNRT). This is what turns "make a track" into one command
  (forge/bounce.sh -> `make render`).

  Self-contained by design: it defines its OWN forge voice (Mnemosyne tape aging
  + light transmutation) and ships it into the NRT server as a \d_recv bundle, so
  a render works without booting the full 317-SynthDef rack. Richer creature
  chains (Relinquished, Proteus) can be swapped into `forgeDef` as they are made
  NRT-safe.

  Driven from sclang (see forge/bounce.sh):
    Server.program = "/Applications/SuperCollider/SuperCollider.app/Contents/Resources/scsynth";
    "brahma/sc/13_nrt_renderer.scd".load;
    ~nrt_renderer.renderSpecimen("/path/in.wav", "/path/out.wav", 12.0, true);
*/

(
~nrt_renderer = (

    // The offline forge voice. Fixed 2-channel input (bounce.sh normalizes to
    // stereo). Returns the SynthDef so renderSpecimen can \d_recv it.
    forgeDef: {
        SynthDef(\brahma_forge_voice, { |buf = 0, dur = 10, amp = 0.9,
                                         age = 0.35, erosion = 0.2, drive = 0.35|
            var sig, rate, wow, flutter, dust, env, core;
            // Tape mechanics (Mnemosyne): wow + flutter modulate playback rate.
            wow     = LFNoise2.kr(0.5).bipolar(age * 0.05);
            flutter = LFNoise1.kr(10).bipolar(age * 0.02);
            rate    = BufRateScale.kr(buf) * (1.0 + wow + flutter);

            sig  = PlayBuf.ar(2, buf, rate, loop: 0, doneAction: 2);
            core = (sig[0] + sig[1]) * 0.5;                 // fold to mono core

            // Erosion (HF loss) + saturation (transmutation).
            core = LPF.ar(core, 18000 - (erosion * 15000));
            core = tanh(core * (1 + (drive * 4)));

            dust = Dust2.ar(age * 10) * 0.05;               // crackle
            env  = EnvGen.kr(Env.linen(0.05, (dur - 0.3).max(0.1), 0.25));
            core = (core + dust) * env * amp;

            Out.ar(0, [core, core]);                        // stereo bounce
        });
    },

    // inputPath   : a stereo 44.1k WAV (bounce.sh guarantees this)
    // outputPath  : destination WAV
    // duration    : render length in seconds
    // exitWhenDone: exit with the NRT server status (for headless sclang)
    renderSpecimen: { |self, inputPath, outputPath, duration = 12.0, exitWhenDone = false|
        var def, score, opts, osc;

        def = self.forgeDef.();
        osc = outputPath ++ ".osc";                          // scratch command file

        score = Score([
            [0.0, [\d_recv, def.asBytes]],                   // ship the SynthDef offline
            [0.0, [\b_allocRead, 0, inputPath, 0, 0]],       // load the food into buffer 0
            [0.0, [\s_new, \brahma_forge_voice, 1000, 0, 0,  // start the voice
                   \buf, 0, \dur, duration]],
            [duration + 0.5, [\c_set, 0, 0]]                 // tail marker
        ]);

        opts = ServerOptions.new
            .numOutputBusChannels_(2)
            .numInputBusChannels_(0)
            .sampleRate_(44100);

        ("NRT render: " ++ inputPath ++ " -> " ++ outputPath
            ++ " (" ++ duration ++ "s)").postln;

        score.recordNRT(
            oscFilePath: osc,
            outputFilePath: outputPath,
            sampleRate: 44100,
            headerFormat: "WAV",
            sampleFormat: "int16",
            options: opts,
            duration: duration + 0.6,
            action: { |exitCode|
                if(exitCode == 0) {
                    ("NRT render complete -> " ++ outputPath).postln;
                } {
                    ("NRT render failed (exit " ++ exitCode ++ ") -> " ++ outputPath).error;
                };
                if(exitWhenDone) { exitCode.exit };
            }
        );
        outputPath
    },

    // ------------------------------------------------------------------------
    // renderPattern — a *pattern* (note events) -> a WAV. Different verb from
    // renderSpecimen, which re-expresses an existing audio file.
    //
    // The score file is plain text, one event per line:
    //
    //     # comment
    //     <time_seconds> <midi_note> <velocity 0..1> <duration_seconds>
    //
    // The wrapper validates JSON/plain input and emits this numeric score.
    //
    // The voice is deliberately a fixed, documented timbre (filtered saw +
    // pulse). It exists so an agent-proposed pattern can be rendered and
    // measured. It is NOT the live engine rack: per-engine timbre is a later
    // concern, and pretending otherwise would make the render lie.
    // ------------------------------------------------------------------------
    patternDef: {
        SynthDef(\brahma_pattern_voice, { |out = 0, freq = 440, amp = 0.3,
                                          dur = 0.5, pan = 0|
            var env, sig, filt;
            env  = EnvGen.kr(Env.perc(0.005, dur, 1, -4), doneAction: 2);
            sig  = Saw.ar(freq, 0.4) + Pulse.ar(freq * 1.004, 0.5, 0.15);
            filt = RLPF.ar(sig, (freq * 6).clip(200, 12000), 0.3);
            sig  = filt * env * amp;
            Out.ar(out, Balance2.ar(sig, sig, pan));
        });
    },

    parsePatternScore: { |self, scorePath|
        var lines, events;
        lines = File.readAllString(scorePath).split($\n);
        events = List.new;
        lines.do { |raw|
            var line, parts, t, note, vel, dur;
            line = raw.stripWhiteSpace;
            if (line.notEmpty and: { line.beginsWith("#").not }) {
                parts = line.split($ ).reject { |p| p.isEmpty };
                if (parts.size >= 4) {
                    t    = parts[0].asFloat;
                    note = parts[1].asFloat;
                    vel  = parts[2].asFloat;
                    dur  = parts[3].asFloat;
                    if (t.notNil and: { note.notNil }) {
                        events.add((time: t, note: note, vel: vel, dur: dur));
                    };
                };
            };
        };
        events
    },

    // scorePath   : plain-text pattern score (see above)
    // outputPath  : destination WAV
    // duration    : render length in seconds (must cover the last event)
    // exitWhenDone: exit with the NRT server status (for headless sclang)
    renderPattern: { |self, scorePath, outputPath, duration = 8.0, exitWhenDone = false|
        var def, events, score, opts, osc, tail;

        def = self.patternDef.();
        events = self.parsePatternScore(scorePath);
        osc = outputPath ++ ".osc";
        tail = 1.2;

        ("NRT pattern render: " ++ events.size ++ " events -> " ++ outputPath
            ++ " (" ++ duration ++ "s)").postln;

        score = Score(
            [[0.0, [\d_recv, def.asBytes]]]
            ++ events.collect { |e, i|
                [
                    e[\time],
                    [\s_new, \brahma_pattern_voice, 2000 + i, 0, 0,
                        \freq, e[\note].midicps,
                        \amp, (e[\vel] * 0.6).clip(0.0, 0.9),
                        \dur, e[\dur].clip(0.02, 30.0),
                        \pan, ((i % 5) - 2) * 0.15]
                ]
            }
            ++ [[duration + 0.5, [\c_set, 0, 0]]]
        );

        opts = ServerOptions.new
            .numOutputBusChannels_(2)
            .numInputBusChannels_(0)
            .sampleRate_(44100);

        score.recordNRT(
            oscFilePath: osc,
            outputFilePath: outputPath,
            sampleRate: 44100,
            headerFormat: "WAV",
            sampleFormat: "int16",
            options: opts,
            duration: duration + tail,
            action: { |exitCode|
                if(exitCode == 0) {
                    ("NRT pattern render complete -> " ++ outputPath).postln;
                } {
                    ("NRT pattern render failed (exit " ++ exitCode ++ ") -> " ++ outputPath).error;
                };
                if(exitWhenDone) { exitCode.exit };
            }
        );
        outputPath
    }
);

"--- BRAHMA: NRT Renderer Loaded (headless bounce ready) ---".postln;
)
