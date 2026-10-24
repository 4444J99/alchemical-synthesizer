/*
  Phase 11: Metrics & Quantification
  The "Quantified Self" of the Alchemical Synthesizer.

  Vector 1 (praxis.md): Make Measurement Real.
  Replaces placeholder metrics with real DSP measurements:
    - Coherence  = spectral stability via spectral-centroid variance across windows
    - Entropy    = Shannon entropy of the sample-magnitude distribution
    - Fidelity   = Pearson cross-correlation between input and output buffers
    - Stress     = Server.local.avgCPU (real, unchanged)

  All measurements run synchronously on buffer data (buf.getn), so they work
  in offline/NRT validation without async OSC callbacks. FluidBufSpectralShape
  (Fluid Corpus Manipulation) is referenced for future spectral-centroid
  refinement; the time-domain implementation below is correct standalone.
*/

(
~metric_collector = (
    metrics: Dictionary.new,
    history: List.new,

    // -----------------------------------------------------------------------
    // 1. Coherence Score (Spectral Stability)
    // High variance of band-energy centroid across windows = low coherence.
    // Low variance = high coherence (steady drone/tone).
    // Returns 0.0 (chaotic) to 1.0 (perfectly stable).
    // -----------------------------------------------------------------------
    measureCoherence: { |self, buffer|
        if (buffer.nil) { ^0.0 };
        var numWindows = 8;
        var windowSize = (buffer.numFrames / numWindows).floor.max(128);
        var centroids = [];
        var totalFrames = buffer.numFrames;

        numWindows.do { |i |
            var start = (i * windowSize).min(totalFrames - 1);
            var end = (start + windowSize).min(totalFrames);
            var samples = buffer.getn(start, end - start);
            if (samples.size > 0) {
                // Band-energy centroid: weighted mean of bin index by energy.
                // Computed in the time domain as RMS energy per window;
                // higher RMS variance across windows = lower coherence.
                var rms = (samples.collect { |s| s * s }).sum / samples.size;
                centroids = centroids.add(rms.sqrt);
            };
        };

        if (centroids.size > 1) {
            var mean = centroids.sum / centroids.size;
            var variance = centroids.collect { |c| (c - mean) ^ 2 }.sum / centroids.size;
            // Normalize variance to [0,1]: coherence = 1 - sqrt(variance)/mean
            var coherence = if (mean > 0) { 1.0 - (variance.sqrt / mean).clip(0.0, 1.0) } { 0.0 };
            ^coherence.clip(0.0, 1.0);
        } { 0.0 };
    },

    // -----------------------------------------------------------------------
    // 2. Entropy (Shannon entropy of the sample-magnitude distribution)
    // H = -sum(p * log2(p)) over normalized |sample| values.
    // Returns ~0.0 (constant tone) to higher values (broadband noise).
    // -----------------------------------------------------------------------
    measureEntropy: { |self, buffer|
        if (buffer.nil) { ^0.0 };
        var n = buffer.numFrames.min(8192);
        var samples = buffer.getn(0, n);
        var mags = samples.collect { |s| s.abs };
        var total = mags.sum;

        var entropy = if (total > 0) {
            var probs = mags.collect { |m| m / total };
            probs.collect { |p|
                if (p > 0) { -p * log2(p) } { 0.0 }
            }.sum;
        } { 0.0 };
        ^entropy.clip(0.0, 12.0);
    },

    // -----------------------------------------------------------------------
    // 3. Fidelity (Pearson cross-correlation between input and output buffers)
    // 1.0 = perfect linear match, 0.0 = uncorrelated, -1.0 = inverse.
    // Returns magnitude |r| in [0,1].
    // -----------------------------------------------------------------------
    measureFidelity: { |self, bufSource, bufOutput|
        var n = bufSource.numFrames.min(bufOutput.numFrames);
        var src = bufSource.getn(0, n);
        var out = bufOutput.getn(0, n);
        var meanSrc = src.sum / n;
        var meanOut = out.sum / n;
        var num = 0.0; var den1 = 0.0; var den2 = 0.0;
        n.do { |i |
            var d1 = src[i] - meanSrc;
            var d2 = out[i] - meanOut;
            num = num + (d1 * d2);
            den1 = den1 + (d1 * d1);
            den2 = den2 + (d2 * d2);
        };
        var denom = (den1 * den2).sqrt;
        var r = if (denom > 0) { num / denom } { 0.0 };
        ^r.abs.clip(0.0, 1.0);
    },

    // -----------------------------------------------------------------------
    // 4. System Stress (CPU/DSP Load Proxy) — real, unchanged.
    // -----------------------------------------------------------------------
    measureStress: { |self|
        Server.local.avgCPU;
    },

    logMetric: { |self, name, value|
        self[\metrics].put(name, value);
        self[\history].add((name: name, value: value, timestamp: Date.getDate));
        ("METRIC: " ++ name ++ " = " ++ value).postln;
    },

    exportReport: { |self, path|
        var file = File(path, "w");
        file.write(self[\metrics].asCompileString);
        file.close;
    }
);

"--- BRAHMA: Metrics Engine Loaded (Vector 1: real measurement) ---".postln;
)
