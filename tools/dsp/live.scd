(
var root = "BRAHMA_REPO_ROOT".getenv;
var failures = 0, check, finish, finished = false;
var packets = List.new;
check = { |condition, label|
    if(condition == true) { ("PASS " ++ label).postln } {
        failures = failures + 1; ("FAIL " ++ label).postln;
    };
};
Server.program = "BRAHMA_SCSYNTH".getenv;
Server.local = Server(\dsp_test, NetAddr("127.0.0.1", "BRAHMA_TEST_PORT".getenv.asInteger));
Server.default = Server.local;
s = Server.local;
s.options.numInputBusChannels = 0;
s.options.numOutputBusChannels = 2;
finish = {
    if(finished.not) {
        finished = true;
        s.quit;
        SystemClock.sched(0.2, {
            if(failures == 0) { "DSP_PASS dummy-server integration".postln; 0.exit } { 1.exit };
            nil
        });
    };
};
SystemClock.sched(15, {
    if(finished.not) { check.(false, "dummy-server integration deadline"); finish.value };
    nil
});
s.waitForBoot({
    {
        var stereo, buffer, result, returned = false, done = false;
        var changing, expected, concurrent, completed, asyncCoherence, asyncEntropy, asyncFidelity, raw;
        var first, second, tail, inst;
        try {
            (root +/+ "brahma/sc/11_metrics.scd").load;
            stereo = Array.fill(16384, { |i|
                var frame = i.div(2), bin = if(i.even) { 32 } { 128 };
                sin(2pi * bin * frame / 1024)
            });
            buffer = Buffer.loadCollection(s, stereo, 2);
            s.sync;
            ~metric_collector.measureBuffer(buffer, { |measurement|
                result = measurement; done = true;
                check.(returned, "Buffer result arrives asynchronously");
            }, 1);
            returned = true;
            while({ done.not }, { 0.01.wait });
            check.(result[\status] == \ok, "real server Buffer is measured");
            check.((result[\centroidHz] - 5512.5).abs < 1,
                "chunked Buffer read preserves stereo frame metadata");
            buffer.free;

            changing = Array.fill(16384, { |i|
                sin(2pi * if(i < 8192) { 32 } { 256 } * i / 1024)
            });
            expected = ~metric_collector.analyzeSamples(changing);
            buffer = Buffer.loadCollection(s, changing, 1);
            s.sync;
            concurrent = Array.newClear(2); completed = 0;
            2.do { |index|
                ~metric_collector.measureBuffer(buffer, { |measurement|
                    concurrent[index] = measurement; completed = completed + 1;
                });
            };
            while({ completed < 2 }, { 0.01.wait });
            concurrent.do { |measurement|
                check.(measurement[\status] == \ok and: { measurement[\windows] == 16 }
                    and: { measurement[\silentWindows] == 0 },
                    "concurrent same-buffer reads preserve all windows");
                check.((measurement[\coherence] - expected[\coherence]).abs < 0.00001,
                    "concurrent same-buffer measurements match source samples");
            };
            completed = 0;
            ~metric_collector.measureCoherence(buffer, { |value| asyncCoherence = value; completed = completed + 1 });
            ~metric_collector.measureEntropy(buffer, { |value| asyncEntropy = value; completed = completed + 1 });
            ~metric_collector.measureFidelity(buffer, buffer, { |value| asyncFidelity = value; completed = completed + 1 });
            BrahmaMetrics.read(buffer, { |data| raw = data; completed = completed + 1 });
            while({ completed < 4 }, { 0.01.wait });
            check.((asyncCoherence - expected[\coherence]).abs < 0.00001,
                "upstream async coherence uses the same bounded sample algorithm");
            check.((asyncEntropy - expected[\entropy]).abs < 0.00001,
                "upstream async entropy uses the same bounded sample algorithm");
            check.(asyncFidelity > 0.999, "upstream Buffer fidelity measures the real captured samples");
            check.(raw.size == 8192, "class sample reader preserves its explicit 8192-frame cap");
            check.(~metric_collector[\bufferReads].isEmpty, "all coalesced Buffer readers release their state");
            buffer.free;

            ~sc_grp = (te: s.defaultGroup);
            (root +/+ "brahma/sc/01_module_registry.scd").load;
            (root +/+ "brahma/sc/16_engine_responders.scd").load;
            (root +/+ "brahma/sc/31_live_gateway.scd").load;
            ~live_gateway[\web] = (sendMsg: { |self ... args| packets.add(args) });
            SynthDef(\dsp_voice_test, { |outBus=0, freq=440, velocity=0.2, gate=1, release=0.08|
                Out.ar(outBus, SinOsc.ar(freq) * velocity * EnvGen.kr(Env.asr(0.001, 1, release), gate, doneAction: 2));
            }).add;
            s.sync;
            ~module_registry.register(\test, \engine, \dsp_voice_test, [], s.defaultGroup, "test voice");
            try { OSCdef(\live_ping).func.value(["/brahma/live/ping"]) } {
                |error| check.(false, "live ping executes: " ++ error.errorString)
            };
            check.(packets.any({ |p| p[0] == "/brahma/live/pong" and: { p[1] == 1 } }),
                "live ping reports module count without Event method collision");

            OSCdef(\live_play).func.value(["/brahma/live/play", \test, \repeat, 60, 0.2, 0.2]);
            first = ~engine_voices[\repeat][\voices][60]; first.register(true);
            0.05.wait;
            OSCdef(\live_play).func.value(["/brahma/live/play", \test, \repeat, 60, 0.2, 0.8]);
            second = ~engine_voices[\repeat][\voices][60]; second.register(true);
            0.25.wait;
            check.(first.isPlaying.not, "retrigger releases displaced synth");
            check.(~engine_voices[\repeat][\voices][60] === second,
                "old auto-release cannot release newer same-note voice");
            OSCdef(\live_panic).func.value(["/brahma/live/panic"]);
            0.1.wait;
            check.(first.isPlaying.not and: { second.isPlaying.not }, "panic leaves neither repeated voice running");
            check.(~live_gateway[\tasks].isEmpty, "panic cancels pending release tasks");

            OSCdef(\live_play).func.value(["/brahma/live/play", \test, \tails, 64, 0.2, 0.05, \release, 2]);
            tail = ~engine_voices[\tails][\voices][64]; tail.register(true);
            0.12.wait;
            check.(~live_voice_count.value == 1, "releasing nodes remain tracked until n_end");
            OSCdef(\live_panic).func.value(["/brahma/live/panic"]);
            0.1.wait;
            check.(tail.isPlaying.not, "panic stops release tails");
            check.(~live_voice_count.value == 0, "panic leaves zero tracked voices");
        } { |error|
            check.(false, error.errorString);
            error.reportError;
        };
        finish.value;
    }.fork(SystemClock);
}, onFailure: { check.(false, "dummy server boot"); finish.value });
)
