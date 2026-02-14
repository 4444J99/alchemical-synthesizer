/*
  Phase 1: CHRONOS Automation
  Parameter lock automation lanes, scene morphing utilities,
  pattern generation, Euclidean rhythms
*/

(
~CHRONOS_AUTO = (

    // ==========================================
    // AUTOMATION LANES
    // ==========================================
    // Per-track automation: param name -> Array of values (one per step)

    setAutomation: { |self, trackIdx, param, values|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            if(track[\automation].isNil) { track[\automation] = Dictionary.new };
            track[\automation][param.asSymbol] = values;
            "CHRONOS: Automation lane '%' set on track %".format(param, trackIdx).postln;
        };
    },

    setAutomationPoint: { |self, trackIdx, param, step, value|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            if(track[\automation].isNil) { track[\automation] = Dictionary.new };
            if(track[\automation][param.asSymbol].isNil) {
                track[\automation][param.asSymbol] = Array.fill(track[\numSteps], nil);
            };
            track[\automation][param.asSymbol][step] = value;
        };
    },

    clearAutomation: { |self, trackIdx, param|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil and: { track[\automation].notNil }) {
            track[\automation].removeAt(param.asSymbol);
        };
    },

    // ==========================================
    // EUCLIDEAN RHYTHM GENERATOR
    // ==========================================
    euclidean: { |self, hits, steps, rotation=0|
        var pattern, bucket, remainder;

        hits = hits.clip(0, steps);

        // Bresenham's line algorithm for Euclidean distribution
        pattern = Array.fill(steps, { |i|
            bucket = bucket ? 0;
            bucket = bucket + hits;
            if(bucket >= steps) {
                bucket = bucket - steps;
                true;
            } { false };
        });

        // Apply rotation
        if(rotation > 0) {
            rotation = rotation % steps;
            pattern = pattern.rotate(rotation.neg);
        };

        ^pattern;
    },

    // Apply Euclidean rhythm to a track
    applyEuclidean: { |self, trackIdx, hits, rotation=0|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            var eucl = self.euclidean(hits, track[\numSteps], rotation);
            eucl.do({ |active, i|
                track[\pattern][i][\active] = active;
            });
            "CHRONOS: Euclidean(%, %, %) applied to track %"
                .format(hits, track[\numSteps], rotation, trackIdx).postln;
        };
    },

    // ==========================================
    // PATTERN GENERATION
    // ==========================================

    // Generate a random pattern with given density
    generateRandom: { |self, trackIdx, density=0.5|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            ~CHRONOS.pushUndoState;
            track[\numSteps].do({ |i|
                track[\pattern][i][\active] = density.coin;
                if(track[\pattern][i][\active]) {
                    track[\pattern][i][\velocity] = rrand(60, 127);
                };
            });
            "CHRONOS: Random pattern (density %) on track %".format(density, trackIdx).postln;
        };
    },

    // Generate a variation of existing pattern
    generateVariation: { |self, trackIdx, amount=0.3|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            ~CHRONOS.pushUndoState;
            track[\numSteps].do({ |i|
                if(amount.coin) {
                    track[\pattern][i][\active] = track[\pattern][i][\active].not;
                };
                if(track[\pattern][i][\active] and: { (amount * 0.5).coin }) {
                    track[\pattern][i][\velocity] = (
                        track[\pattern][i][\velocity] + rrand(-20, 20)
                    ).clip(1, 127);
                };
            });
            "CHRONOS: Variation (%) on track %".format(amount, trackIdx).postln;
        };
    },

    // Generate fill (dense pattern in last N steps)
    generateFill: { |self, trackIdx, fillLength=4, density=0.75|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            ~CHRONOS.pushUndoState;
            var fillStart = track[\numSteps] - fillLength;
            var eucl = self.euclidean(
                (fillLength * density).round.asInteger.clip(1, fillLength),
                fillLength
            );

            fillLength.do({ |i|
                var step = fillStart + i;
                track[\pattern][step][\active] = eucl[i];
                if(eucl[i]) {
                    // Rising velocity
                    track[\pattern][step][\velocity] = (80 + (i / fillLength * 47)).round.asInteger;
                };
            });
            "CHRONOS: Fill (% steps, %) on track %".format(fillLength, density, trackIdx).postln;
        };
    },

    // Clear all steps on a track
    clearPattern: { |self, trackIdx|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            ~CHRONOS.pushUndoState;
            track[\numSteps].do({ |i|
                track[\pattern][i][\active] = false;
                track[\pattern][i][\velocity] = 100;
                track[\pattern][i][\note] = 60;
                track[\pattern][i][\pLocks] = nil;
            });
            "CHRONOS: Track % pattern cleared".format(trackIdx).postln;
        };
    },

    // Rotate pattern N steps
    rotatePattern: { |self, trackIdx, amount=1|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            ~CHRONOS.pushUndoState;
            track[\pattern] = track[\pattern].rotate(amount);
            "CHRONOS: Track % rotated by %".format(trackIdx, amount).postln;
        };
    },

    // Reverse pattern
    reversePattern: { |self, trackIdx|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil) {
            ~CHRONOS.pushUndoState;
            track[\pattern] = track[\pattern].reverse;
            "CHRONOS: Track % reversed".format(trackIdx).postln;
        };
    },

    // Double pattern length (repeat)
    doublePattern: { |self, trackIdx|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil and: { (track[\numSteps] * 2) <= 128 }) {
            ~CHRONOS.pushUndoState;
            var original = track[\pattern].deepCopy;
            track[\pattern] = original ++ original;
            track[\numSteps] = track[\numSteps] * 2;
            "CHRONOS: Track % doubled to % steps".format(trackIdx, track[\numSteps]).postln;
        };
    },

    // Halve pattern length
    halvePattern: { |self, trackIdx|
        var track = ~CHRONOS[\tracks][trackIdx];
        if(track.notNil and: { track[\numSteps] > 1 }) {
            ~CHRONOS.pushUndoState;
            var newLen = (track[\numSteps] / 2).ceil.asInteger.max(1);
            track[\pattern] = track[\pattern].copyRange(0, newLen - 1);
            track[\numSteps] = newLen;
            "CHRONOS: Track % halved to % steps".format(trackIdx, newLen).postln;
        };
    }
);

// ==========================================
// OSC RESPONDERS — Automation & Generation
// ==========================================
OSCdef(\chronos_auto_point, { |msg|
    ~CHRONOS_AUTO.setAutomationPoint(
        msg[1].asInteger, msg[2].asString, msg[3].asInteger, msg[4].asFloat);
}, "/chronos/automation/point");

OSCdef(\chronos_auto_clear, { |msg|
    ~CHRONOS_AUTO.clearAutomation(msg[1].asInteger, msg[2].asString);
}, "/chronos/automation/clear");

OSCdef(\chronos_gen_euclidean, { |msg|
    ~CHRONOS_AUTO.applyEuclidean(msg[1].asInteger, msg[2].asInteger,
        msg[3] !? _.asInteger ?? 0);
}, "/chronos/gen/euclidean");

OSCdef(\chronos_gen_random, { |msg|
    ~CHRONOS_AUTO.generateRandom(msg[1].asInteger, msg[2] !? _.asFloat ?? 0.5);
}, "/chronos/gen/random");

OSCdef(\chronos_gen_variation, { |msg|
    ~CHRONOS_AUTO.generateVariation(msg[1].asInteger, msg[2] !? _.asFloat ?? 0.3);
}, "/chronos/gen/variation");

OSCdef(\chronos_gen_fill, { |msg|
    ~CHRONOS_AUTO.generateFill(msg[1].asInteger,
        msg[2] !? _.asInteger ?? 4, msg[3] !? _.asFloat ?? 0.75);
}, "/chronos/gen/fill");

OSCdef(\chronos_clear, { |msg| ~CHRONOS_AUTO.clearPattern(msg[1].asInteger) }, "/chronos/clear");
OSCdef(\chronos_rotate, { |msg| ~CHRONOS_AUTO.rotatePattern(msg[1].asInteger, msg[2].asInteger) }, "/chronos/rotate");
OSCdef(\chronos_reverse, { |msg| ~CHRONOS_AUTO.reversePattern(msg[1].asInteger) }, "/chronos/reverse");
OSCdef(\chronos_double, { |msg| ~CHRONOS_AUTO.doublePattern(msg[1].asInteger) }, "/chronos/double");
OSCdef(\chronos_halve, { |msg| ~CHRONOS_AUTO.halvePattern(msg[1].asInteger) }, "/chronos/halve");

// Golem legacy generative aliases
OSCdef(\golem_gen_variation_alias, { |msg|
    ~CHRONOS_AUTO.generateVariation(msg[1].asInteger, msg[2] !? _.asFloat ?? 0.3);
}, "/golem/gen/variation");

OSCdef(\golem_gen_fill_alias, { |msg|
    ~CHRONOS_AUTO.generateFill(msg[1].asInteger,
        msg[2] !? _.asInteger ?? 4, msg[3] !? _.asFloat ?? 0.75);
}, "/golem/gen/fill");

"--- BRAHMA: CHRONOS Automation Engine Online ---".postln;
)
