/*
  Phase 13: Non-Real-Time (NRT) Rendering for Specimen Generation
*/

(
~NRT_RENDERER = (

    // Render a "Specimen" to disk
    // Input: A 10-second audio file (The "Food")
    // Process: Fed through Relinquished -> Transmuted
    // Output: A new WAV file (The "Result")

    renderSpecimen: { |self, inputPath, outputPath|
        var score, buf;

        score = Score([
            [0.0, [\b_allocRead, 0, inputPath]],
            [0.0, [\s_new, \relinquished_ia, 1000, 0, 0, \inBusA, 0]],
            [0.0, [\s_new, \relinquished_bc, 1001, 0, 0, \inBus, 0]],
            [10.0, [\c_set, 0, 0]] // Finish
        ]);

        // This requires the 'nrt' server option configuration in real usage
        "NRT Render requested for: ".postln;
        ("Input: " ++ inputPath).postln;
        ("Output: " ++ outputPath).postln;

        // Score.recordNRT(...) would go here
    }
);

"--- BRAHMA: NRT Renderer Loaded ---".postln;
)
