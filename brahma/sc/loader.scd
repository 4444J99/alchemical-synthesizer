/*
  Brahma Master Loader
  Complete load order for the Alchemical Synthesizer Meta-Rack

  CRITICAL: All file loads after 01_infrastructure.scd must happen
  inside s.doWhenBooted to guarantee ~SC_GRP, ~SC_BUS, ~BRAHMA_REGISTRY
  are initialized before dependent files execute.
*/

(
var root = thisProcess.nowExecutingPath.dirname;

// === 01: Infrastructure (boots server, creates globals) ===
(root +/+ "01_infrastructure.scd").load;

// Wait for server boot to complete before loading anything that
// depends on ~SC_GRP, ~SC_BUS, ~BRAHMA_REGISTRY, etc.
s.doWhenBooted({

    // === 01B: Arbitration Engine ===
    (root +/+ "01_arbitration_engine.scd").load;

    // === 01C: Module Registry ===
    (root +/+ "01_module_registry.scd").load;

    // === 02: Tuning & Input Systems ===
    (root +/+ "02_microtonality.scd").load;
    (root +/+ "02_midi_mpe.scd").load;

    // === 03: Proteus & MAW ===
    (root +/+ "03_proteus_maw.scd").load;

    // === 04: Relinquished & Fusion Core ===
    (root +/+ "04_relinquished.scd").load;
    (root +/+ "04_fusion_core.scd").load;

    // === 05: Organisms & Creatures ===
    (root +/+ "05_sampler_creatures.scd").load;
    (root +/+ "05_sampler_creatures_stereo.scd").load;
    (root +/+ "05_agent_smith.scd").load;
    (root +/+ "05_ditto.scd").load;

    // === 06: Stacking & Evolution ===
    (root +/+ "06_typhon.scd").load;

    // === 07: Safety & Stability ===
    (root +/+ "07_safety.scd").load;

    // === 08: Patch Bay ===
    (root +/+ "08_patch_bay.scd").load;

    // === 09: CHRONOS Master Sequencer ===
    (root +/+ "09_chronos_core.scd").load;
    (root +/+ "09_chronos_clock.scd").load;
    (root +/+ "09_chronos_tracks.scd").load;
    (root +/+ "09_chronos_midi.scd").load;
    (root +/+ "09_chronos_automation.scd").load;

    // === 10-13: Validation & Metrics ===
    (root +/+ "10_validation.scd").load;
    (root +/+ "11_metrics.scd").load;
    (root +/+ "12_test_bench.scd").load;
    (root +/+ "13_nrt_renderer.scd").load;

    // === 14: Visual Cortex ===
    (root +/+ "14_visual_cortex.scd").load;

    // === 15: Golem Percussion Organism ===
    (root +/+ "15_percussion_suite.scd").load;
    (root +/+ "15_golem_fx.scd").load;
    (root +/+ "15_golem_patterns.scd").load;
    (root +/+ "15_golem_sequencer.scd").load;
    (root +/+ "15_golem.scd").load;

    // === 16: Synthesis Engines ===
    (root +/+ "16_synthesis_engines.scd").load;

    // === 16B: Engine Voice Responders ===
    (root +/+ "16_engine_responders.scd").load;

    // === 17-20: Make Noise Modules ===
    (root +/+ "17_make_noise_functions.scd").load;
    (root +/+ "18_make_noise_filters.scd").load;
    (root +/+ "19_make_noise_time.scd").load;
    (root +/+ "20_make_noise_oscillators.scd").load;
    (root +/+ "20_make_noise_sequencers.scd").load;
    (root +/+ "20_make_noise_utilities.scd").load;

    // === 21-22: Effects Rack ===
    (root +/+ "21_fx_dynamics.scd").load;
    (root +/+ "21_fx_eq.scd").load;
    (root +/+ "22_fx_distortion.scd").load;
    (root +/+ "22_fx_modulation.scd").load;
    (root +/+ "22_fx_spatial.scd").load;
    (root +/+ "22_fx_spectral.scd").load;
    (root +/+ "22_fx_time.scd").load;

    // === 23-24: Standard Modular Modules ===
    (root +/+ "23_modular_oscillators.scd").load;
    (root +/+ "23_modular_filters.scd").load;
    (root +/+ "23_modular_amplifiers.scd").load;
    (root +/+ "23_modular_envelopes.scd").load;
    (root +/+ "23_modular_modulation.scd").load;
    (root +/+ "24_modular_clock.scd").load;
    (root +/+ "24_modular_sequencers.scd").load;
    (root +/+ "24_modular_utilities.scd").load;

    // === 25: Elektron Machine Emulations ===
    (root +/+ "25_elektron_machines.scd").load;
    (root +/+ "25_elektron_octatrack.scd").load;

    // === 26: Interaction & Controllers ===
    (root +/+ "26_interaction_controllers.scd").load;
    (root +/+ "26_interaction_sensors.scd").load;

    // === 27: Generative Systems ===
    (root +/+ "27_generative_modules.scd").load;
    (root +/+ "27_generative_sequencers.scd").load;

    // === 27B: DAEMON-CHRONOS Clock Bridge ===
    (root +/+ "27_daemon_clock_bridge.scd").load;

    // === 28: Audio Management ===
    (root +/+ "28_audio_monitoring.scd").load;
    (root +/+ "28_audio_recording.scd").load;
    (root +/+ "28_audio_presets.scd").load;
    (root +/+ "28_audio_sync.scd").load;

    // === 29: Deploy IMMUNE Governor (must be last in signal chain) ===
    // Stereo IMMUNE on hardware outputs — final safety net
    Synth(\immune_governor, [\inBus, 0, \outBus, 0, \threshold, 0.9], ~SC_GRP[\rr], \addToTail);
    Synth(\immune_governor, [\inBus, 1, \outBus, 1, \threshold, 0.9], ~SC_GRP[\rr], \addToTail);
    "--- BRAHMA: IMMUNE Governor Deployed (stereo, threshold 0.9) ---".postln;

    // === 30: Demo Patch (generative hello-world) ===
    (root +/+ "30_demo_patch.scd").load;

    "--- BRAHMA SYSTEM ONLINE ---".postln;
});
)
