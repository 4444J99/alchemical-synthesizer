/*
  Brahma Master Loader
*/

(
var root = thisProcess.nowExecutingPath.dirname;

// 1. Infrastructure
(root +/+ "01_infrastructure.scd").load;
(root +/+ "01_arbitration_engine.scd").load;

// 2. Proteus & MAW
(root +/+ "03_proteus_maw.scd").load;

// 3. Relinquished
(root +/+ "04_relinquished.scd").load;

// 4. Fusion Core
(root +/+ "04_fusion_core.scd").load;

// 5. Sampler Creatures
(root +/+ "05_sampler_creatures.scd").load;
(root +/+ "05_sampler_creatures_stereo.scd").load;
(root +/+ "05_agent_smith.scd").load;
(root +/+ "05_ditto.scd").load;

// 6. Typhon
(root +/+ "06_typhon.scd").load;

// 7. Safety
(root +/+ "07_safety.scd").load;

// 10. Validation
(root +/+ "10_validation.scd").load;

"--- BRAHMA SYSTEM ONLINE ---".postln;
)
