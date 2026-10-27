/*
  Phase 11: Measurements from actual samples (SuperCollider core only).

  analyzeSamples takes interleaved samples plus sample-rate/channel metadata.
  It analyzes at most 64 complete, non-overlapping 1024-sample windows by
  default. Each window is mean-centered and Hann-windowed before a real FFT.
  Silent/DC-only windows are omitted; at least two active windows are required.

  coherence: 1 - stddev(spectral power centroid) / mean(centroid), clipped 0..1.
             This is centroid stability, not a claim of perceptual fidelity.
  entropy:   mean Shannon entropy of one-sided spectral power, in bits.
             A Hann-windowed tone has small nonzero entropy due to leakage.
  fidelity:  absolute zero-lag Pearson correlation of aligned sample arrays.
             Gain, DC offset and polarity are ignored; latency is NOT corrected.

  Missing, invalid, short or silent input returns status: unavailable and nil
  metric values, never a fabricated zero. measureCoherence/measureEntropy are
  scalar conveniences for sample arrays. Use analyzeFile for offline/NRT WAVs,
  or measureBuffer(buffer, action) for asynchronous live Buffer acquisition.
  NRT servers cannot answer interactive Buffer.getn requests.
*/


BrahmaMetrics {
    classvar <collector;

    *initClass {
        collector = (
    metrics: Dictionary.new,
    history: List.new,
    bufferReads: IdentityDictionary.new,

    unavailable: { |self, reason|
        (status: \unavailable, reason: reason)
    },

    validWindowSize: { |self, size|
        size.isKindOf(Integer) and: { size >= 64 } and: { size <= 16384 }
        and: { size.bitAnd(size - 1) == 0 }
    },

    // Validate the sample layout before selecting a channel. Do not fold
    // stereo to mono: opposite-polarity channels would otherwise cancel.
    prepareSamples: { |self, samples, numChannels=1, channel=0|
        var reason, frames, data;
        case
        { samples.isKindOf(SequenceableCollection).not } { reason = \missing_samples }
        { samples.isEmpty } { reason = \empty_samples }
        { numChannels.isKindOf(Integer).not or: { numChannels <= 0 } } {
            reason = \invalid_channels
        }
        { channel.isKindOf(Integer).not or: { channel < 0 or: { channel >= numChannels } } } {
            reason = \invalid_channel
        }
        { (samples.size % numChannels) != 0 } { reason = \partial_frame }
        { samples.every({ |value|
            value.isKindOf(SimpleNumber) and: { value.isNaN.not } and: { value.abs < inf }
        }).not } { reason = \nonfinite_or_nonnumeric_samples };

        if(reason.notNil) { self.unavailable(reason) } {
            frames = samples.size.div(numChannels);
            data = Array.fill(frames, { |i| samples[(i * numChannels) + channel] });
            (status: \ok, data: data, frames: frames)
        }
    },

    analyzeSamples: { |self, samples, sampleRate=44100, numChannels=1, channel=0, windowSize=1024|
        var prepared = self.prepareSamples(samples, numChannels, channel);
        var result = prepared;
        var data, peak, windowCount, window, cosTable, centroids, entropies;
        var mean, variance, entropy;
        if(sampleRate.isKindOf(SimpleNumber).not or: {
            sampleRate <= 0 or: { sampleRate.isNaN or: { sampleRate.abs >= inf } }
        }) {
            result = self.unavailable(\invalid_sample_rate);
        } {
            if(self.validWindowSize(windowSize).not) {
                result = self.unavailable(\invalid_window_size);
            } {
                if(prepared[\status] == \ok) {
                    data = prepared[\data];
                    windowCount = data.size.div(windowSize).min(64);
                    peak = data.collect(_.abs).maxItem;
                    case
                    { windowCount < 2 } { result = self.unavailable(\insufficient_frames) }
                    { peak == 0 } { result = self.unavailable(\silent_input) }
                    {
                        window = Signal.hanningWindow(windowSize);
                        cosTable = Signal.fftCosTable(windowSize);
                        centroids = List.new;
                        entropies = List.new;
                        windowCount.do { |frame|
                            var values, dc, real, spectrum, power, total, probabilities;
                            // Scale before the float FFT to avoid overflow. Spectral
                            // probability and centroid are invariant to this gain.
                            values = Array.fill(windowSize, { |i|
                                data[(frame * windowSize) + i] / peak
                            });
                            dc = values.mean;
                            real = Signal.fill(windowSize, { |i| (values[i] - dc) * window[i] });
                            spectrum = real.fft(Signal.newClear(windowSize), cosTable);
                            power = Array.fill(windowSize.div(2) + 1, { |bin|
                                var energy = spectrum.real[bin].squared + spectrum.imag[bin].squared;
                                if(bin > 0 and: { bin < windowSize.div(2) }) { energy * 2 } { energy }
                            });
                            total = power.sum;
                            if(total > 1e-12) {
                                probabilities = power / total;
                                centroids.add(probabilities.collect { |p, bin|
                                    p * bin * sampleRate / windowSize
                                }.sum);
                                entropies.add(probabilities.collect { |p|
                                    if(p > 0) { p.neg * p.log2 } { 0.0 }
                                }.sum);
                            };
                        };
                        if(centroids.size < 2) {
                            result = self.unavailable(\insufficient_active_windows);
                        } {
                            mean = centroids.mean;
                            variance = centroids.collect({ |value| (value - mean).squared }).mean;
                            entropy = entropies.mean;
                            result = (
                                status: \ok,
                                coherence: (1 - (variance.sqrt / mean)).clip(0, 1),
                                entropy: entropy,
                                entropyNormalized: entropy / (windowSize.div(2) + 1).log2,
                                centroidHz: mean,
                                sampleRate: sampleRate,
                                numChannels: numChannels,
                                channel: channel,
                                windowSize: windowSize,
                                windows: centroids.size,
                                silentWindows: windowCount - centroids.size,
                                analyzedFrames: windowCount * windowSize,
                                algorithm: \hann_power_centroid_cv
                            );
                        };
                    };
                };
            };
        };
        result
    },

    // A callback in the sample-rate position selects asynchronous Buffer input.
    // Arrays keep the explicit sample-rate/channel signature used by analyzeSamples.
    metricValue: { |self, kind, input, sampleRate=44100, numChannels=1, channel=0|
        var value, action;
        if(sampleRate.isKindOf(Function)) {
            action = sampleRate;
            if(input.isKindOf(Buffer)) {
                self.measureBuffer(input, { |measurement| action.value(measurement[kind]) }, channel);
            } {
                value = self.analyzeSamples(input, 44100, numChannels, channel)[kind];
                action.value(value);
            };
        } {
            if(input.isKindOf(Buffer)) { Error("Buffer measurement requires an action callback").throw };
            value = self.analyzeSamples(input, sampleRate, numChannels, channel)[kind];
        };
        value
    },

    measureCoherence: { |self, input, sampleRate=44100, numChannels=1, channel=0|
        self.metricValue(\coherence, input, sampleRate, numChannels, channel)
    },

    measureEntropy: { |self, input, sampleRate=44100, numChannels=1, channel=0|
        self.metricValue(\entropy, input, sampleRate, numChannels, channel)
    },

    fidelitySamples: { |self, source, output, numChannels=1, channel=0|
        var src = self.prepareSamples(source, numChannels, channel);
        var out = self.prepareSamples(output, numChannels, channel);
        var a, b, peakA, peakB, meanA, meanB, numerator=0.0, denA=0.0, denB=0.0, denominator;
        var result;
        if(src[\status] == \ok and: { out[\status] == \ok } and: {
            src[\frames] == out[\frames] and: { src[\frames] >= 2 }
        }) {
            a = src[\data]; b = out[\data];
            peakA = a.collect(_.abs).maxItem; peakB = b.collect(_.abs).maxItem;
            if(peakA > 0 and: { peakB > 0 }) {
                a = a / peakA; b = b / peakB;
                meanA = a.mean; meanB = b.mean;
                a.size.do { |i|
                    var da = a[i] - meanA, db = b[i] - meanB;
                    numerator = numerator + (da * db);
                    denA = denA + da.squared; denB = denB + db.squared;
                };
                denominator = (denA * denB).sqrt;
                if(denominator > 1e-12) { result = (numerator / denominator).abs.clip(0, 1) };
            };
        };
        result
    },

    measureFidelity: { |self, source, output, numChannels=1, channel=0|
        var action, value;
        if(numChannels.isKindOf(Function)) { action = numChannels; numChannels = 1 };
        if(source.isKindOf(Buffer) or: { output.isKindOf(Buffer) }) {
            if(action.isNil) { Error("Buffer fidelity requires an action callback").throw };
            if(source.isKindOf(Buffer) and: { output.isKindOf(Buffer) } and: {
                source.numChannels == output.numChannels and: {
                    source.numFrames == output.numFrames and: { source.sampleRate == output.sampleRate }
                }
            }) {
                self.readBuffer(source, { |a|
                    self.readBuffer(output, { |b|
                        action.value(if(a[\status] == \ok and: { b[\status] == \ok }) {
                            self.fidelitySamples(a[\samples], b[\samples], a[\numChannels], channel)
                        } { nil });
                    });
                });
            } { action.value(nil) };
        } {
            value = self.fidelitySamples(source, output, numChannels, channel);
            action.value(value);
        };
        value
    },

    // Caller-supplied evidence is structural provenance, not a signature or a
    // proof of capture identity. Derivation/capture IDs must be supplied by the
    // eventual end-to-end measurement pipeline.
    attachMeasurements: { |self, traits, coherence, entropy, fidelity|
        var result;
        if(traits.isKindOf(Dictionary).not) { Error("Expected a trait dictionary").throw };
        result = traits.deepCopy.putAll((confidence: fidelity, provenance: \measured,
            measurements: (coherence: coherence, entropy: entropy, fidelity: fidelity,
                source: \caller_supplied, fidelityDefinition: \absolute_aligned_pearson)));
        if(BrahmaContracts.validMeasurement(result, 0).not) { Error("Invalid measurement evidence").throw };
        result
    },

    // SoundFile lives in the language process, so this also works after NRT.
    analyzeFile: { |self, path, channel=0, windowSize=1024|
        var file, samples, result = self.unavailable(\file_unreadable);
        if(self.validWindowSize(windowSize).not) {
            result = self.unavailable(\invalid_window_size);
        } {
            if(path.isKindOf(String) and: { File.exists(path) }) {
                file = SoundFile.openRead(path);
                if(file.notNil) {
                    protect {
                        samples = FloatArray.newClear(file.numFrames.min(windowSize * 64) * file.numChannels);
                        file.readData(samples);
                        result = self.analyzeSamples(samples, file.sampleRate, file.numChannels, channel, windowSize);
                    } { file.close };
                };
            };
        };
        result.put(\source, \soundfile);
        result
    },

    // Coalesce reads per server/buffer. Track each requested offset exactly
    // once: stock getToFloatArray counts every reply for a bufnum, so concurrent
    // reads can otherwise finish early with a partially zero-filled array.
    // Callers should keep the captured buffer stable until measurement finishes.
    readBuffer: { |self, buffer, action, channel=0|
        var done = false, rate, channels, count, reads, callbacks, bufnum;
        var samples, chunks, responder, routine, finish, offset;
        if(action.isKindOf(Function).not) { Error("readBuffer requires an action callback").throw };
        if(buffer.isKindOf(Buffer).not or: { buffer.bufnum.isNil } or: {
            buffer.numFrames.isKindOf(Integer).not or: { buffer.numFrames <= 0 }
        } or: {
            buffer.numChannels.isKindOf(Integer).not or: { buffer.numChannels.inclusivelyBetween(1, 64).not }
        }) {
            action.value(self.unavailable(\invalid_buffer));
        } {
            if(buffer.server.serverRunning.not) {
                action.value(self.unavailable(\server_not_running));
            } {
                rate = buffer.sampleRate;
                channels = buffer.numChannels;
                count = buffer.numFrames.min(65536).min(262144.div(channels)) * channels;
                bufnum = buffer.bufnum;
                reads = self[\bufferReads][buffer.server];
                if(reads.isNil) {
                    reads = Dictionary.new;
                    self[\bufferReads][buffer.server] = reads;
                };
                callbacks = reads[bufnum];
                if(callbacks.notNil) {
                    callbacks.add([action, channel]);
                } {
                    callbacks = List.new.add([action, channel]);
                    reads[bufnum] = callbacks;
                    samples = FloatArray.newClear(count);
                    chunks = Dictionary.new;
                    offset = 0;
                    while({ offset < count }, {
                        chunks[offset] = (count - offset).min(1633);
                        offset = offset + 1633;
                    });
                    finish = { |reason|
                        if(done.not) {
                            done = true;
                            responder.free;
                            routine.stop;
                            reads.removeAt(bufnum);
                            if(reads.isEmpty) { self[\bufferReads].removeAt(buffer.server) };
                            callbacks.do { |entry|
                                // One caller's exception cannot prevent delivery
                                // to the other coalesced measurement requests.
                                try {
                                    entry[0].value(if(reason.isNil) {
                                        (status: \ok, samples: samples, sampleRate: rate, numChannels: channels)
                                    } { self.unavailable(reason) });
                                } { |error| error.reportError };
                            };
                        };
                    };
                    responder = OSCFunc({ |msg|
                        var size = chunks[msg[2]];
                        if(done.not and: { msg[1] == bufnum } and: { size.notNil }
                            and: { msg[3] == size } and: { msg.size == (size + 4) }) {
                            samples.overWrite(FloatArray.newFrom(msg.copyToEnd(4)), msg[2]);
                            chunks.removeAt(msg[2]);
                            if(chunks.isEmpty) { finish.value(nil) };
                        };
                    }, '/b_setn', buffer.server.addr);
                    routine = Routine({
                        var position = 0;
                        while({ done.not and: { position < count } }, {
                            buffer.server.listSendMsg(buffer.getnMsg(position, (count - position).min(1633)));
                            position = position + 1633;
                            0.01.wait;
                        });
                    }).play(SystemClock);
                    SystemClock.sched(3.1, { finish.value(\buffer_timeout); nil });
                };
            };
        };
        nil
    },

    measureBuffer: { |self, buffer, action, channel=0|
        if(action.isKindOf(Function).not) { Error("measureBuffer requires an action callback").throw };
        self.readBuffer(buffer, { |result|
            action.value(if(result[\status] == \ok) {
                self.analyzeSamples(result[\samples], result[\sampleRate], result[\numChannels], channel)
            } { result });
        });
        nil
    },

    measureStress: { |self|
        if(Server.local.serverRunning) { Server.local.avgCPU } { nil }
    },

    logMetric: { |self, name, value|
        self[\metrics].put(name, value);
        self[\history].add((name: name, value: value, timestamp: Date.getDate));
        ("METRIC: " ++ name ++ " = " ++ value).postln;
    },

    exportReport: { |self, path|
        var file = File(path, "w");
        protect { file.write(self[\metrics].asCompileString) } { file.close };
    }
);
    }

    *samples { |input|
        if(input.isNil) { ^[] };
        if(input.isSequenceableCollection.not or: {
            input.any { |value| BrahmaContracts.finiteNumber(value).not }
        }) { Error("Expected finite numeric samples").throw };
        ^input;
    }

    *coherence { |input, sampleRate=44100, channels=1, channel=0|
        ^collector.analyzeSamples(this.samples(input), sampleRate, channels, channel)[\coherence];
    }

    *entropy { |input, sampleRate=44100, channels=1, channel=0|
        ^collector.analyzeSamples(this.samples(input), sampleRate, channels, channel)[\entropy];
    }

    *fidelity { |source, output, channels=1|
        var a = this.samples(source), b = this.samples(output), values;
        if(channels.isKindOf(Integer).not or: { channels < 1 or: { channels > 64 } }) { ^nil };
        values = Array.fill(channels, { |channel| collector.fidelitySamples(a, b, channels, channel) });
        ^if(values.any(_.isNil)) { nil } { values.mean };
    }

    *read { |input, action|
        var data;
        if(input.isKindOf(Buffer)) {
            if(action.isKindOf(Function).not) { Error("Buffer read requires an action callback").throw };
            collector.readBuffer(input, { |result|
                action.value(if(result[\status] == \ok) {
                    result[\samples].copyRange(0, (result[\samples].size.min(8192 * result[\numChannels])) - 1)
                } { nil });
            });
            ^nil;
        };
        data = this.samples(input); action.value(data); ^data;
    }

    *measure { |kind, input, action, sampleRate=44100, channels=1, channel=0|
        var value;
        if([\coherence, \entropy].includes(kind).not) { Error("Unknown spectral measurement").throw };
        if(input.isKindOf(Buffer)) {
            if(action.isKindOf(Function).not) { Error("Buffer measurement requires an action callback").throw };
            collector.measureBuffer(input, { |result| action.value(result[kind]) }, channel);
            ^nil;
        };
        value = collector.analyzeSamples(this.samples(input), sampleRate, channels, channel)[kind];
        action.value(value); ^value;
    }

    *stability { |centroids|
        var mean, variance;
        if(centroids.isSequenceableCollection.not or: { centroids.size < 2 }) { ^nil };
        if(centroids.any { |value| BrahmaContracts.finiteNumber(value).not }) { ^nil };
        mean = centroids.mean;
        if(mean <= 1e-12) { ^nil };
        variance = centroids.collect { |value| (value - mean).squared }.mean;
        ^(1.0 - (variance.sqrt / mean)).clip(0, 1);
    }

    // Explicit optional algorithm. Installing FluCoMa never silently changes
    // the core Hann-power metric. Its scalar has distinct spectral semantics.
    *fluidCoherence { |buffer, action, numWindows=8, overlap=0.5|
        var fluid = \FluidBufSpectralShape.asClass, features, window, hop, frames;
        var done = false, finish;
        if(action.isKindOf(Function).not) { Error("FluCoMa measurement requires an action callback").throw };
        if(fluid.isNil) { Error("FluCoMa spectral analysis is unavailable").throw };
        if(buffer.isKindOf(Buffer).not or: { buffer.server.serverRunning.not } or: {
            buffer.bufnum.isNil or: { buffer.numFrames.isKindOf(Integer).not }
        }) { action.value(nil); ^nil };
        frames = buffer.numFrames.min(8192);
        if(frames < 16) { action.value(nil); ^nil };
        window = (frames / numWindows.clip(2, 64)).floor.asInteger.max(16).nextPowerOfTwo;
        hop = (window * (1 - overlap.clip(0, 0.9))).asInteger.max(1);
        features = Buffer(buffer.server);
        finish = { |value|
            if(done.not) { done = true; features.free; action.value(value) };
        };
        try {
            fluid.process(buffer.server, source: buffer, numFrames: frames, features: features,
                select: [\centroid], windowSize: window, hopSize: hop, padding: 0, action: {
                    if(done.not) {
                        // The plugin allocates the feature buffer in the server;
                        // query its actual layout before acquiring raw samples.
                        features.updateInfo({ |updated|
                            if(done.not) {
                                collector.readBuffer(updated, { |result|
                                    var values;
                                    if(result[\status] == \ok) {
                                        values = result[\samples].clump(buffer.numChannels).flop.collect { |channel|
                                            this.stability(channel)
                                        };
                                    };
                                    finish.value(if(values.notNil and: { values.notEmpty and: { values.every(_.notNil) } }) {
                                        values.mean
                                    } { nil });
                                });
                            };
                        });
                    };
                });
        } { |error| error.reportError; finish.value(nil) };
        SystemClock.sched(5.0, { finish.value(nil); nil });
        ^nil;
    }
}
