(
var root = "BRAHMA_REPO_ROOT".getenv;
var work = "BRAHMA_TEST_TMP".getenv;
var failures = 0, check, tone, changing, noise, stereo, result, other, file;
check = { |condition, label|
    if(condition == true) { ("PASS " ++ label).postln } {
        failures = failures + 1;
        ("FAIL " ++ label).postln;
    };
};
(root +/+ "brahma/sc/11_metrics.scd").load;
check.(~metric_collector.notNil, "collector loads");
if(~metric_collector.notNil) {
    tone = Array.fill(8192, { |i| sin(2pi * 32 * i / 1024) });
    changing = Array.fill(8192, { |i|
        sin(2pi * if((i.div(1024) % 2) == 0) { 32 } { 256 } * i / 1024)
    });
    thisThread.randSeed = 427;
    noise = Array.fill(8192, { 1.0.rand2 });
    stereo = [tone, Array.fill(8192, { |i| sin(2pi * 128 * i / 1024) })].lace(16384);
    result = ~metric_collector.analyzeSamples(tone);
    check.(result[\status] == \ok, "tone is measured");
    check.(result[\coherence] > 0.999, "stationary spectral centroid is stable");
    check.((result[\centroidHz] - 1378.125).abs < 1, "centroid is in Hz");
    check.(result[\entropy] < 2, "tone has concentrated spectral power");
    check.(~metric_collector.analyzeSamples(changing)[\coherence] < 0.3,
        "equal-RMS frequency changes lower spectral stability");
    other = ~metric_collector.analyzeSamples(noise);
    check.(other[\entropy] > 7, "noise has broad spectral power");
    check.(other[\entropy] > (result[\entropy] + 4), "tone and noise entropy differ");
    check.(~metric_collector.measureCoherence(tone) > 0.999, "scalar coherence uses samples");
    check.(~metric_collector.measureEntropy(noise) > 7, "scalar entropy uses samples");
    [nil, [], [1, 2], Array.fill(8192, 0), Array.fill(8192, 1),
        [0, inf], [0, 0.0/0.0], [0, "bad"]].do { |samples|
        other = ~metric_collector.analyzeSamples(samples);
        check.(other[\status] == \unavailable, "invalid/empty/silent data is unavailable");
        check.(other[\coherence].isNil and: { other[\entropy].isNil }, "unavailable is not zero");
    };
    check.(~metric_collector.analyzeSamples(tone, 0)[\status] == \unavailable,
        "invalid sample rate is rejected");
    check.(~metric_collector.analyzeSamples(stereo, 44100, 2, 2)[\status] == \unavailable,
        "invalid channel is rejected");
    check.(~metric_collector.analyzeSamples([1,2,3], 44100, 2)[\status] == \unavailable,
        "partial interleaved frame is rejected");
    other = ~metric_collector.analyzeSamples(stereo, 44100, 2, 1);
    check.((other[\centroidHz] - 5512.5).abs < 1, "stereo channel selection preserves frame indexing");
    check.((~metric_collector.measureFidelity(tone, tone) - 1).abs < 0.00001,
        "identical waveform fidelity is one");
    check.((~metric_collector.measureFidelity(tone, tone * -0.3 + 0.1) - 1).abs < 0.00001,
        "absolute Pearson fidelity documents gain/DC/polarity invariance");
    check.(~metric_collector.measureFidelity(tone, noise) < 0.1, "unrelated signals have low fidelity");
    check.(~metric_collector.measureFidelity(tone, tone.copyRange(0, 4095)).isNil,
        "unaligned lengths are unavailable");
    check.(~metric_collector.measureFidelity(Array.fill(16, 0), Array.fill(16, 0)).isNil,
        "zero variance fidelity is undefined");
    check.(~metric_collector.measureFidelity(nil, tone).isNil, "missing fidelity input is unavailable");
    file = SoundFile.openWrite(work +/+ "metric-stereo.wav", "WAV", "float", 2, 44100);
    file.writeData(FloatArray.newFrom(stereo)); file.close;
    other = ~metric_collector.analyzeFile(work +/+ "metric-stereo.wav", 1);
    check.(other[\status] == \ok, "offline SoundFile adapter reads real samples");
    check.((other[\centroidHz] - 5512.5).abs < 1, "offline adapter honors channel metadata");
    check.(~metric_collector.analyzeFile(work +/+ "missing.wav")[\status] == \unavailable,
        "missing sound file is unavailable");
    other = nil;
    ~metric_collector.measureBuffer(nil, { |measurement| other = measurement });
    check.(other[\status] == \unavailable, "buffer adapter reports invalid input through callback");
};
if(failures == 0) { "DSP_PASS metrics".postln; 0.exit } { 1.exit };
)
