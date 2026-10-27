/* Native donor audition. Extracted rack SynthDefs are compiled, never replaced.
   Each score has independent buffers and ordered source -> module -> limiter.
   This is an offline Forge entry point, not an automatically booted live patch. */
(
~donor_rack = (
    writeScore: { |self, definitionPath, args, stereoPath, monoPath, scorePath, duration, outputBus=8, controlMaps, mode=0|
        var definition, source, master, outputs, channels, messages;
        definition = File.readAllString(definitionPath).interpret;
        if(definition.isKindOf(SynthDef).not) { Error("Donor definition did not compile").throw };
        outputs = definition.children.select({ |ugen|
            [\Out, \ReplaceOut, \OffsetOut].includes(ugen.class.name) and: { ugen.rate == \audio }
        });
        channels = if(outputs.isEmpty) { 2 } { outputs.collect({ |ugen| ugen.inputs.size - 1 }).maxItem.clip(1, 2) };
        source = SynthDef(\donor_source, {
            var sig = PlayBuf.ar(2, 0, BufRateScale.kr(0), loop: 1);
            var mono = Mix(sig) * 0.5, env, chain, pitch, onset;
            env = (Amplitude.kr(mono, 0.005, 0.1) * 4).clip(0, 1);
            chain = FFT(LocalBuf(1024), mono);
            pitch = Pitch.kr(mono, initFreq: 220, minFreq: 50, maxFreq: 2000);
            onset = Trig1.kr(Onsets.kr(chain, 0.3) + Impulse.kr(0), 0.04);
            Out.ar(2, sig); Out.ar(4, mono);
            Out.ar(6, [mono, (sig[0] - sig[1]) * 0.5]);
            Out.kr(0, [env, (SpecCentroid.kr(chain) / 10000).clip(0, 1),
                SpecFlatness.kr(chain), onset, pitch[0].clip(50, 2000),
                DelayN.kr(env, 0.25, 0.12), env > 0.005, Amplitude.kr(mono) > 0.95]);
        });
        master = SynthDef(\donor_master, {
            var sig = if(mode == 2) { In.ar(2, 2) * In.kr(outputBus).abs.tanh } { In.ar(outputBus, channels) };
            var env = EnvGen.kr(Env.linen(0.01, (duration - 0.03).max(0.01), 0.02));
            // Even generators without amp/freq controls inherit donor dynamics.
            // This is explicit source-envelope resynthesis, not an audio insert.
            if([1, 3].includes(mode)) { sig = sig * In.kr(0) };
            if(channels == 1) { sig = sig ! 2 };
            ReplaceOut.ar(0, Limiter.ar(LeakDC.ar(sig), 0.9, 0.005) * env);
        });
        messages = [
            [0.0, [\d_recv, source.asBytes]],
            [0.0, [\d_recv, definition.asBytes]],
            [0.0, [\d_recv, master.asBytes]],
            [0.0, [\b_allocRead, 0, stereoPath, 0, 0]],
            [0.0, [\b_allocRead, 1, monoPath, 0, 0]],
            [0.0, [\b_allocReadChannel, 2, stereoPath, 0, 0, 0]],
            [0.0, [\b_allocReadChannel, 3, stereoPath, 0, 0, 1]],
        ];
        if(mode == 3) {
            var file = SoundFile.openRead(monoPath), data = FloatArray.newClear(8192);
            file.readData(data); file.close;
            4.do({ |i|
                var table = data.copyRange(i * 2048, ((i + 1) * 2048) - 1).as(Signal).asWavetable;
                messages = messages.add([0.0, [\b_alloc, 16 + i, table.size, 1]]);
                messages = messages.add([0.0, [\b_setn, 16 + i, 0, table.size] ++ table]);
            });
        };
        messages = messages ++ [
            [0.0, [\s_new, \donor_source, 1000, 1, 1]],
            [0.0, [\s_new, definition.name, 1001, 1, 1] ++ args],
            [0.0, [\n_map, 1001] ++ (controlMaps ? [])],
            [0.0, [\s_new, \donor_master, 1002, 1, 1]],
            // Release graph nodes before NRT plugin teardown. SC 3.14 on this
            // host crashes in Graph_Dtor if looping voices survive World_Cleanup.
            [duration - 0.001, [\g_freeAll, 1]],
            [duration, [\c_set, 0, 0]]
        ];
        Score(messages).write(scorePath);
        ("DONOR_COMPILED " ++ definition.name).postln;
    }
);
)
