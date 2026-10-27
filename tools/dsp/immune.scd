(
var root = "BRAHMA_REPO_ROOT".getenv;
var work = "BRAHMA_TEST_TMP".getenv;
var immune, source, score;
var opts = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0);
(root +/+ "brahma/sc/07_safety.scd").load;
immune = SynthDescLib.global[\immune_governor].def;
source = SynthDef(\dsp_test_source, {
    Out.ar(0, [SinOsc.ar(1000) * 5, SinOsc.ar(440) * 0.2]);
});
Score.program = "BRAHMA_SCSYNTH".getenv;
score = Score([
    [0, [\d_recv, source.asBytes]],
    [0, [\d_recv, immune.asBytes]],
    [0.01, [\s_new, \dsp_test_source, 1000, 0, 1]],
    [0.01, [\s_new, \immune_governor, 1001, 3, 1000, \inBus, 0, \outBus, 0, \threshold, 0.9]],
    [0.01, [\s_new, \immune_governor, 1002, 3, 1001, \inBus, 1, \outBus, 1, \threshold, 0.9]],
    [1, [\c_set, 0, 0]]
]);
score.recordNRT(
    oscFilePath: work +/+ "immune.osc",
    outputFilePath: work +/+ "immune.wav",
    sampleRate: 44100, headerFormat: "WAV", sampleFormat: "float",
    options: opts, duration: 1,
    action: { |exitCode|
        if(exitCode == 0) { "DSP_PASS NRT render (waveform checked by Python)".postln };
        exitCode.exit;
    }
);
)
