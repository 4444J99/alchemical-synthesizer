/*
  Brahma Master Loader
*/

(
var root = thisProcess.nowExecutingPath.dirname;

// 1. Infrastructure
(root +/+ "01_infrastructure.scd").load;

// 2. Proteus & MAW
(root +/+ "03_proteus_maw.scd").load;

// 3. Relinquished
(root +/+ "04_relinquished.scd").load;

// 4. Fusion Core
(root +/+ "04_fusion_core.scd").load;

// 5. Sampler Creatures
(root +/+ "05_sampler_creatures.scd").load;

// 6. Typhon
(root +/+ "06_typhon.scd").load;

// 7. Safety
(root +/+ "07_safety.scd").load;

"--- BRAHMA SYSTEM ONLINE ---".postln;
)
