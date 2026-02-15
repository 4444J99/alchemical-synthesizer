/*
  Tier 1: VOICE — Demo Patch
  Self-playing generative composition that boots with the system.
  Combines Prima Materia, MOIRAI Markov melody, Euclidean rhythm,
  Lorenz attractor modulation, and reverb FX.

  /brahma/demo/start — begin
  /brahma/demo/stop  — silence
*/

(
~DEMO_PATCH = (
    active: false,
    synths: List.new,
    buses: IdentityDictionary.new,
    instances: List.new,

    start: { |self|
        if(self[\active].not) {
            self[\active] = true;

            // Allocate internal buses
            var melodyBus = Bus.audio(s, 2);
            var reverbBus = Bus.audio(s, 2);
            self[\buses][\melody] = melodyBus;
            self[\buses][\reverb] = reverbBus;

            // 1. Create MOIRAI Markov chain trained on pentatonic intervals
            var markov = ~MOIRAI.(12);
            // Train on pentatonic scale degrees (C D E G A in MIDI offsets)
            var pentatonic = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 12, 7];
            markov.train(pentatonic);
            markov.setTemperature(0.7);
            self[\instances].add([\moirai, markov]);

            // 2. Create Euclidean rhythm generator E(5, 8)
            var euclidean = ~DAEMON_EUCLIDEAN_EXT.(8, 5, 2, 0);
            euclidean.generate;
            self[\instances].add([\euclidean, euclidean]);

            // 3. Create Lorenz attractor for filter modulation
            var lorenzBusX = Bus.control(s, 1);
            var lorenzBusY = Bus.control(s, 1);
            var lorenzBusZ = Bus.control(s, 1);
            self[\buses][\lorenzX] = lorenzBusX;
            self[\buses][\lorenzY] = lorenzBusY;
            self[\buses][\lorenzZ] = lorenzBusZ;

            var lorenz = Synth(\daemon_lorenz, [
                \outBusX, lorenzBusX.index,
                \outBusY, lorenzBusY.index,
                \outBusZ, lorenzBusZ.index,
                \sigma, 10, \rho, 28, \beta, 2.667,
                \rate, 2.0, \scale, 0.03
            ]);
            self[\synths].add(lorenz);

            // 4. Create a reverb on the reverb bus → main out
            var reverb = Synth(\aion_hall, [
                \inBus, melodyBus.index,
                \outBus, 0,
                \mix, 0.35,
                \decay, 3.0,
                \damping, 0.4
            ], ~SC_GRP[\rr], \addToHead);
            self[\synths].add(reverb);

            // 5. Start the generative Tdef
            Tdef(\demo_patch_gen, {
                var baseNote = 48; // C3
                var tempo = ~CHRONOS[\tempo] ? 120;

                loop {
                    var stepDur = 60 / tempo / 4; // 16th notes

                    // Advance Euclidean
                    euclidean.advance;
                    var gate = euclidean.gate;
                    var vel = euclidean.velocity;

                    if(gate > 0) {
                        // Get next Markov interval
                        var interval = (markov.next * 24).round.asInteger;
                        var note = baseNote + interval;
                        note = note.clip(36, 84);

                        var freq = note.midicps;

                        // Read Lorenz for cutoff modulation
                        var cutoff;
                        lorenzBusX.get({ |v| cutoff = v.linexp(0, 1, 400, 8000) });
                        cutoff = cutoff ? 2000;

                        // Spawn a Prima Materia voice
                        var voice = Synth(\prima_materia, [
                            \freq, freq,
                            \velocity, vel * 0.5, // Gentle volume
                            \gate, 1,
                            \outBus, melodyBus.index,
                            \cutoff, cutoff,
                            \resonance, 1.5,
                            \filterType, 0,
                            \atk, 0.01,
                            \dec, 0.2,
                            \sus, 0.4,
                            \rel, 0.6,
                            \osc1Type, 1, // saw
                            \osc2Type, 0, // sine
                            \osc2Detune, 5,
                            \osc2Level, 0.3
                        ], ~SC_GRP[\te], \addToTail);

                        // Release after a fraction of the step
                        {
                            (stepDur * 0.7).wait;
                            voice.set(\gate, 0);
                        }.fork;
                    };

                    // Update tempo from CHRONOS if running
                    if(~CHRONOS.notNil and: { ~CHRONOS[\tempo].notNil }) {
                        tempo = ~CHRONOS[\tempo];
                    };

                    stepDur.wait;
                };
            }).play;

            // Broadcast state
            if(~VISUAL_CORTEX.notNil) {
                ~VISUAL_CORTEX.target.sendMsg("/brahma/demo/state", 1);
            };

            "--- BRAHMA: Demo Patch PLAYING ---".postln;
            "  Prima Materia + MOIRAI melody + E(5,8) rhythm + Lorenz filter mod + Hall reverb".postln;
        };
    },

    stop: { |self|
        if(self[\active]) {
            self[\active] = false;

            // Stop the Tdef
            Tdef(\demo_patch_gen).stop;

            // Free all synths
            self[\synths].do({ |s| s.free });
            self[\synths] = List.new;

            // Free buses
            self[\buses].do({ |b| b.free });
            self[\buses] = IdentityDictionary.new;

            // Clear instances
            self[\instances] = List.new;

            // Broadcast state
            if(~VISUAL_CORTEX.notNil) {
                ~VISUAL_CORTEX.target.sendMsg("/brahma/demo/state", 0);
            };

            "--- BRAHMA: Demo Patch STOPPED ---".postln;
        };
    }
);

// ==========================================
// OSC RESPONDERS
// ==========================================
OSCdef(\demo_start, { ~DEMO_PATCH.start }, "/brahma/demo/start");
OSCdef(\demo_stop, { ~DEMO_PATCH.stop }, "/brahma/demo/stop");

// Auto-start after 1 second delay
{ 1.0.wait; ~DEMO_PATCH.start; }.fork;

"--- BRAHMA: Demo Patch Loaded (auto-start in 1s) ---".postln;
)
