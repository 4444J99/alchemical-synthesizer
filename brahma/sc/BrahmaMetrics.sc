/* Spectral measurements of samples, with explicit asynchronous Buffer reads. */
BrahmaMetrics {
    *samples { |input|
        if(input.isNil) { ^[] };
        if(input.isSequenceableCollection.not) { Error("Expected sample collection").throw };
        if(input.any { |value| BrahmaContracts.finiteNumber(value).not }) {
            Error("Metrics require finite numeric samples").throw;
        };
        ^input;
    }

    *spectrum { |input|
        var samples = this.samples(input), size, real, transform;
        if(samples.size < 2) { ^[0.0] };
        size = samples.size.nextPowerOfTwo;
        real = Signal.newClear(size);
        samples.do { |value, i| real[i] = value * (0.5 - (0.5 * cos(2pi * i / (samples.size - 1)))) };
        transform = real.fft(Signal.newClear(size), Signal.fftCosTable(size));
        ^transform.magnitude.copyRange(0, size.div(2));
    }

    *centroid { |input|
        var magnitudes = this.spectrum(input), total = magnitudes.sum;
        if(total <= 1e-12) { ^0.0 };
        ^magnitudes.collect { |value, bin| value * bin }.sum / total;
    }

    *stability { |centroids|
        var mean, variance;
        if(centroids.size < 2) { ^0.0 };
        mean = centroids.mean;
        if(mean <= 1e-12) { ^0.0 };
        variance = centroids.collect { |value| (value - mean).squared }.mean;
        ^(1.0 - (variance.sqrt / mean)).clip(0.0, 1.0);
    }

    *coherence { |input, numWindows=8, overlap=0.5|
        var samples = this.samples(input), size, hop, centroids;
        if(samples.size < 16) { ^0.0 };
        numWindows = numWindows.asInteger.clip(2, 64); overlap = overlap.clip(0.0, 0.9);
        size = (samples.size / (1 + ((numWindows - 1) * (1 - overlap)))).floor.asInteger.max(8);
        hop = (size * (1 - overlap)).floor.asInteger.max(1);
        centroids = Array.fill(numWindows, { |i|
            var start = (i * hop).min(samples.size - size);
            this.centroid(samples.copyRange(start, start + size - 1));
        });
        ^this.stability(centroids);
    }

    *entropy { |input|
        var magnitudes = this.spectrum(input), total = magnitudes.sum;
        if(total <= 1e-12) { ^0.0 };
        ^magnitudes.collect { |value|
            var probability = value / total;
            if(probability > 0) { probability.neg * probability.log2 } { 0.0 };
        }.sum.clip(0.0, 12.0);
    }

    *fidelity { |source, output, channels=1|
        var a = this.samples(source), b = this.samples(output), frames, values;
        channels = channels.asInteger.max(1);
        frames = a.size.min(b.size).div(channels);
        if(frames < 2) { ^0.0 };
        values = Array.fill(channels, { |channel|
            var x = Array.fill(frames, { |i| a[(i * channels) + channel] });
            var y = Array.fill(frames, { |i| b[(i * channels) + channel] });
            var dx = x - x.mean, dy = y - y.mean;
            var denominator = (dx.squared.sum * dy.squared.sum).sqrt;
            if(denominator > 1e-12) { ((dx * dy).sum / denominator).clip(0.0, 1.0) } { 0.0 };
        });
        ^values.mean;
    }

    *read { |input, action|
        if(input.isKindOf(Buffer)) {
            if(action.isNil) { Error("Buffer measurements are asynchronous: supply an action callback").throw };
            input.loadToFloatArray(count: input.numFrames.min(8192),
                action: { |data| action.value(this.samples(data)) });
            ^nil;
        };
        ^this.samples(input);
    }

    *measure { |kind, input, action, numWindows=8, overlap=0.5|
        var data, value;
        if(input.isKindOf(Buffer)) {
            if(action.isNil) { Error("Buffer measurement requires action").throw };
            if(kind == \coherence and: { \FluidBufSpectralShape.asClass.notNil }) {
                ^this.fluidCoherence(input, action, numWindows, overlap);
            };
            this.read(input, { |samples|
                var channels = samples.clump(input.numChannels).flop;
                action.value(channels.collect { |channel| this.perform(kind, channel, numWindows, overlap) }.mean ? 0.0);
            });
            ^nil;
        };
        data = this.read(input); value = this.perform(kind, data, numWindows, overlap);
        action.value(value); ^value;
    }

    *fluidCoherence { |buffer, action, numWindows=8, overlap=0.5|
        var features, window, hop, frames = buffer.numFrames.min(8192);
        if(frames < 16) { action.value(0.0); ^nil };
        window = (frames / numWindows.clip(2, 64)).floor.asInteger.max(16).nextPowerOfTwo;
        hop = (window * (1 - overlap.clip(0, 0.9))).asInteger.max(1);
        features = Buffer(buffer.server);
        \FluidBufSpectralShape.asClass.process(buffer.server, source: buffer, numFrames: frames, features: features,
            select: [\centroid], windowSize: window, hopSize: hop, padding: 0, action: {
                features.loadToFloatArray(action: { |data|
                    features.free;
                    action.value(this.samples(data).clump(buffer.numChannels).flop.collect { |channel| this.stability(channel) }.mean ? 0.0);
                });
            });
        ^nil;
    }
}
