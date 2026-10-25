(
var server, options, check;
check = { |condition, label| if(condition.not) { Error("FAIL: " ++ label).throw }; ("PASS: " ++ label).postln };
options = ServerOptions.new.numInputBusChannels_(0).numOutputBusChannels_(2).memSize_(8192).maxNodes_(128);
server = Server(\brahmaMetricTest, NetAddr("127.0.0.1", NetAddr.langPort + 1), options);
Server.program = "/Applications/Supercollider/SuperCollider.app/Contents/Resources/scsynth";
(thisProcess.nowExecutingPath.dirname.dirname +/+ "11_metrics.scd").load;
server.waitForBoot({
    Routine({
        var source, output, features, samples, stereo;
        try {
            samples = Signal.fill(4096, { |i| sin(2pi * 64 * i / 4096) });
            source = Buffer.loadCollection(server, samples);
            output = Buffer.loadCollection(server, samples);
            features = Buffer(server);
            stereo = Buffer.loadCollection(server, Signal.fill(18000, { 0.25 }), 2);
            server.sync;
            FluidDataSet.version(server);
            FluidBufSpectralShape.processBlocking(server, source: source, features: features, select: [\centroid], windowSize: 512, hopSize: 256);
            server.sync;
            features.loadToFloatArray(action: { |data|
                try {
                    check.value(data.size > 0 and: { data.every { |n| n.isNumber and: { n.isNaN.not } } }, "real FluCoMa server plugin processes audio buffer");
                    ~metric_collector.measureCoherence(source, { |coherence|
                        try {
                            [\coherence, coherence].postln; check.value(coherence > 0.95, "async FluCoMa coherence");
                            ~metric_collector.measureEntropy(source, { |entropy|
                                try {
                                    check.value(entropy >= 0 and: { entropy < 4 }, "async spectral entropy");
                                    ~metric_collector.measureFidelity(source, output, { |fidelity|
                                        try {
                                            check.value(fidelity > 0.999, "async Buffer fidelity");
                                            BrahmaMetrics.read(stereo, { |data|
                                                try {
                                                    check.value(data.size == 16384, "stereo reads are capped at 8192 frames");
                                                    source.free; output.free; features.free; stereo.free;
                                                    server.quit;
                                                    "BRAHMA_TEST_PASS".postln; 0.exit;
                                                } { |err| err.reportError; server.quit; 1.exit };
                                            });
                                        } { |err| err.reportError; server.quit; 1.exit };
                                    });
                                } { |err| err.reportError; server.quit; 1.exit };
                            });
                        } { |err| err.reportError; server.quit; 1.exit };
                    });
                } { |err| err.reportError; server.quit; 1.exit };
            });
        } { |err| err.reportError; server.quit; 1.exit };
    }).play;
}, onFailure: { "FAIL: isolated server boot".postln; 1.exit });
)
