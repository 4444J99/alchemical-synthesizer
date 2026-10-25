/*
  Phase 11: Metrics & Quantification
  The "Quantified Self" of the Alchemical Synthesizer.

  Vector 1 (praxis.md): Make Measurement Real.
  Replaces placeholder metrics with real DSP measurements:
    - Coherence  = spectral stability via spectral-centroid variance across windows
    - Entropy    = Shannon entropy of the spectral magnitude distribution
    - Fidelity   = Pearson cross-correlation between input and output buffers
    - Stress     = Server.local.avgCPU (real, unchanged)

  Sample collections return synchronously. Server Buffer measurements require
  an action callback. Coherence uses FluCoMa when available, with a native FFT
  fallback; entropy uses the actual spectral magnitude distribution.
*/

(
["sound", "idea", "product", "cosmos"].do { |name|
    var path = thisProcess.nowExecutingPath.dirname.dirname +/+ "substrate" +/+ (name ++ ".json");
    if(AdamKadmon.loadContract(path).isNil) { Error("Cannot load substrate contract: " ++ path).throw };
};
~metric_collector = (
    metrics: Dictionary.new,
    history: List.new,

    // -----------------------------------------------------------------------
    // 1. Coherence Score (Spectral Stability)
    // High variance of band-energy centroid across windows = low coherence.
    // Low variance = high coherence (steady drone/tone).
    // Returns 0.0 (chaotic) to 1.0 (perfectly stable).
    // -----------------------------------------------------------------------
    measureCoherence: { |self, buffer, action, numWindows=8, overlap=0.5|
        BrahmaMetrics.measure(\coherence, buffer, action, numWindows, overlap);
    },

    // -----------------------------------------------------------------------
    // 2. Entropy (Shannon entropy of the spectral magnitude distribution)
    // H = -sum(p * log2(p)) over normalized |sample| values.
    // Returns ~0.0 (constant tone) to higher values (broadband noise).
    // -----------------------------------------------------------------------
    measureEntropy: { |self, buffer, action|
        BrahmaMetrics.measure(\entropy, buffer, action);
    },

    // -----------------------------------------------------------------------
    // 3. Fidelity (Pearson cross-correlation between input and output buffers)
    // 1.0 = perfect linear match, 0.0 = uncorrelated, -1.0 = inverse.
    // Returns positive correlation in [0,1]; inversion is not faithful reconstruction.
    // -----------------------------------------------------------------------
    measureFidelity: { |self, source, output, action, channels=1|
        var value;
        if(source.isKindOf(Buffer) or: { output.isKindOf(Buffer) }) {
            if(source.isKindOf(Buffer).not or: { output.isKindOf(Buffer).not }) {
                Error("Both fidelity inputs must be Buffers or sample collections").throw;
            };
            if(source.numChannels != output.numChannels) { Error("Fidelity channel counts differ").throw };
            if(action.isNil) { Error("Buffer fidelity requires action").throw };
            BrahmaMetrics.read(source, { |a|
                BrahmaMetrics.read(output, { |b| action.value(BrahmaMetrics.fidelity(a, b, source.numChannels)) });
            });
            nil;
        } {
            value = BrahmaMetrics.fidelity(source, output, channels);
            action.value(value); value;
        };
    },

    // -----------------------------------------------------------------------
    // 4. System Stress (CPU/DSP Load Proxy) — real, unchanged.
    // -----------------------------------------------------------------------
    measureStress: { |self|
        Server.local.avgCPU;
    },

    // Attach the measured evidence used by FSAP's confidence gate. The caller
    // supplies domain traits; spectral values themselves are not confidence.
    attachMeasurements: { |self, traits, coherence, entropy, fidelity|
        var values = [coherence, entropy, fidelity];
        if(values.any { |value| BrahmaContracts.finiteNumber(value).not }) {
            Error("Cannot attest nonfinite measurements").throw;
        };
        traits.copy.putAll((confidence: fidelity, provenance: \measured,
            measurements: (coherence: coherence, entropy: entropy, fidelity: fidelity)));
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
