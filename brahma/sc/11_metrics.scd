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


// Shared bounded metrics. Loading phase 11 does not replace in-flight Buffer
// read state, and optional plugins do not change the default algorithm.
(
["sound", "idea", "product", "cosmos"].do { |name|
    var path = thisProcess.nowExecutingPath.dirname.dirname +/+ "substrate" +/+ (name ++ ".json");
    if(AdamKadmon.loadContract(path).isNil) { Error("Cannot load substrate contract: " ++ path).throw };
};
~metric_collector = BrahmaMetrics.collector;
"--- BRAHMA: Sample Metrics Loaded (spectral centroid stability, spectral entropy, aligned correlation) ---".postln;
)
