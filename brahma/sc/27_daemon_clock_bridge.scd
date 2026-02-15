/*
  Tier 3: SINEW — DAEMON-CHRONOS Clock Bridge
  Bridges language-side generative modules (DAEMON_MACHINA, MOIRAI, GENESIS,
  ARBOR_VITAE, EUCLIDEAN_EXT, PROB_MATRIX) with the CHRONOS master clock.

  Each registered target has a clock division (in PPQN subdivisions) and optional
  CV/gate bus mappings. The master tick loop calls tick/next/step/advance
  on each target when the tick count aligns with its division.
*/

(
~DAEMON_CLOCK_BRIDGE = (
    targets: IdentityDictionary.new,

    // Register a generative module with the clock bridge
    // type: \machina, \moirai, \genesis, \arbor, \euclidean, \probmatrix
    // division: clock division in 16th notes (1 = every 16th, 2 = every 8th, 4 = every quarter, etc.)
    // cvBus/gateBus: optional control bus indices for output
    register: { |self, name, type, instance, division, cvBus, gateBus|
        self[\targets].put(name.asSymbol, (
            name: name.asSymbol,
            type: type.asSymbol,
            instance: instance,
            division: division ? 1,
            cvBus: cvBus,
            gateBus: gateBus,
            active: true
        ));
        "DAEMON_CLOCK_BRIDGE: Registered '%' (%, div=%)".format(name, type, division).postln;
    },

    unregister: { |self, name|
        self[\targets].removeAt(name.asSymbol);
        "DAEMON_CLOCK_BRIDGE: Unregistered '%'".format(name).postln;
    },

    // Called from the CHRONOS master tick loop
    // tickCount is in PPQN (96 per quarter note)
    // We convert division (in 16th notes) to PPQN ticks: div * (96/4) = div * 24
    tick: { |self, tickCount|
        self[\targets].do({ |target|
            if(target[\active]) {
                var ppqnPerStep = target[\division] * 24; // 24 PPQN ticks per 16th note
                if((tickCount % ppqnPerStep.round.asInteger) == 0) {
                    self.triggerTarget(target);
                };
            };
        });
    },

    // Dispatch tick to the appropriate module type
    triggerTarget: { |self, target|
        var inst = target[\instance];
        if(inst.notNil) {
            switch(target[\type],
                \machina, {
                    inst.tick;
                    if(target[\cvBus].notNil) {
                        Bus(\control, target[\cvBus], 1, s).set(inst.cv);
                    };
                    if(target[\gateBus].notNil) {
                        Bus(\control, target[\gateBus], 1, s).set(inst.gate);
                    };
                },
                \moirai, {
                    var val = inst.next;
                    if(target[\cvBus].notNil) {
                        Bus(\control, target[\cvBus], 1, s).set(val);
                    };
                },
                \genesis, {
                    inst.step;
                    if(target[\cvBus].notNil) {
                        Bus(\control, target[\cvBus], 1, s).set(inst.cv);
                    };
                    if(target[\gateBus].notNil) {
                        Bus(\control, target[\gateBus], 1, s).set(inst.density);
                    };
                },
                \arbor, {
                    var val = inst.cv;
                    if(target[\cvBus].notNil) {
                        Bus(\control, target[\cvBus], 1, s).set(val);
                    };
                },
                \euclidean, {
                    inst.advance;
                    if(target[\gateBus].notNil) {
                        Bus(\control, target[\gateBus], 1, s).set(inst.gate);
                    };
                    if(target[\cvBus].notNil) {
                        Bus(\control, target[\cvBus], 1, s).set(inst.velocity);
                    };
                },
                \probmatrix, {
                    inst.advance;
                    // For prob matrix, we write each row's gate to sequential buses
                    if(target[\gateBus].notNil) {
                        var activeRows = inst.getActiveRows;
                        activeRows.do({ |gate, i|
                            Bus(\control, target[\gateBus] + i, 1, s).set(gate);
                        });
                    };
                }
            );
        };
    },

    // Toggle active state
    setActive: { |self, name, state|
        var target = self[\targets][name.asSymbol];
        if(target.notNil) {
            target[\active] = state;
        };
    },

    // Set division for a target
    setDivision: { |self, name, division|
        var target = self[\targets][name.asSymbol];
        if(target.notNil) {
            target[\division] = division.clip(1, 64);
        };
    }
);

// ==========================================
// OSC RESPONDERS
// ==========================================
OSCdef(\daemon_clock_register, { |msg|
    var name = msg[1].asSymbol;
    var type = msg[2].asSymbol;
    var division = (msg[3] ? 1).asInteger;
    var cvBus = if(msg.size > 4) { msg[4].asInteger } { nil };
    var gateBus = if(msg.size > 5) { msg[5].asInteger } { nil };

    // Look up the instance from the appropriate registry
    var instance = switch(type,
        \machina, { ~DAEMON_MACHINA_INSTANCES[name] },
        \moirai, { ~MOIRAI_INSTANCES[name] },
        \genesis, { ~GENESIS_INSTANCES[name] },
        \arbor, {
            var entry = ~DAEMON_SEQ_INSTANCES[name];
            if(entry.notNil and: { entry[0] == \arbor }) { entry[1] } { nil };
        },
        \euclidean, {
            var entry = ~DAEMON_SEQ_INSTANCES[name];
            if(entry.notNil and: { entry[0] == \euclidean }) { entry[1] } { nil };
        },
        \probmatrix, {
            var entry = ~DAEMON_SEQ_INSTANCES[name];
            if(entry.notNil and: { entry[0] == \probmatrix }) { entry[1] } { nil };
        }
    );

    if(instance.notNil) {
        ~DAEMON_CLOCK_BRIDGE.register(name, type, instance, division, cvBus, gateBus);
    } {
        "DAEMON_CLOCK_BRIDGE: Instance '%' not found for type '%'".format(name, type).postln;
    };
}, "/daemon/clock/register");

OSCdef(\daemon_clock_unregister, { |msg|
    var name = msg[1].asSymbol;
    ~DAEMON_CLOCK_BRIDGE.unregister(name);
}, "/daemon/clock/unregister");

OSCdef(\daemon_clock_set_division, { |msg|
    var name = msg[1].asSymbol;
    var division = msg[2].asInteger;
    ~DAEMON_CLOCK_BRIDGE.setDivision(name, division);
}, "/daemon/clock/division");

OSCdef(\daemon_clock_toggle, { |msg|
    var name = msg[1].asSymbol;
    var active = msg[2].asInteger > 0;
    ~DAEMON_CLOCK_BRIDGE.setActive(name, active);
}, "/daemon/clock/toggle");

"--- BRAHMA: DAEMON-CHRONOS Clock Bridge Online ---".postln;
)
