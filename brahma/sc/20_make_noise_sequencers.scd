/*
  Phase 3: Make Noise Sequencer & Controller Clones
  Rene, Pressure Points, PrssPNT, TEMPI
*/

(
// ==========================================
// CARTESIAN_MAZE — Rene (Cartesian Sequencer)
// ==========================================
// Language-side sequencer: X/Y/Z axes, snake/skip/state modes
~CARTESIAN_MAZE = (
    // 4x4 grid of CV values
    grid: Array.fill(4, { Array.fill(4, { rrand(0.0, 1.0) }) }),
    gateGrid: Array.fill(4, { Array.fill(4, true) }),

    // Current position
    posX: 0,
    posY: 0,

    // Modes: \forward, \reverse, \pendulum, \random, \snake
    modeX: \forward,
    modeY: \forward,

    // Pendulum state
    dirX: 1,
    dirY: 1,

    // Output buses
    cvBus: nil,
    gateBus: nil,

    init: { |self|
        self[\cvBus] = Bus.control(s, 1);
        self[\gateBus] = Bus.control(s, 1);
        ~PATCH_BAY.registerSource(\rene_cv, self[\cvBus], \control, "Rene CV out");
        ~PATCH_BAY.registerSource(\rene_gate, self[\gateBus], \control, "Rene gate out");
        "CARTESIAN_MAZE: Initialized".postln;
    },

    // Advance X axis
    advanceX: { |self|
        case
        { self[\modeX] == \forward } { self[\posX] = (self[\posX] + 1) % 4 }
        { self[\modeX] == \reverse } { self[\posX] = (self[\posX] - 1 + 4) % 4 }
        { self[\modeX] == \pendulum } {
            self[\posX] = self[\posX] + self[\dirX];
            if(self[\posX] >= 3 or: { self[\posX] <= 0 }) {
                self[\dirX] = self[\dirX].neg;
            };
            self[\posX] = self[\posX].clip(0, 3);
        }
        { self[\modeX] == \random } { self[\posX] = 4.rand }
        { self[\modeX] == \snake } {
            if((self[\posY] % 2) == 0) {
                self[\posX] = (self[\posX] + 1) % 4;
            } {
                self[\posX] = (self[\posX] - 1 + 4) % 4;
            };
        };
    },

    // Advance Y axis
    advanceY: { |self|
        case
        { self[\modeY] == \forward } { self[\posY] = (self[\posY] + 1) % 4 }
        { self[\modeY] == \reverse } { self[\posY] = (self[\posY] - 1 + 4) % 4 }
        { self[\modeY] == \pendulum } {
            self[\posY] = self[\posY] + self[\dirY];
            if(self[\posY] >= 3 or: { self[\posY] <= 0 }) {
                self[\dirY] = self[\dirY].neg;
            };
            self[\posY] = self[\posY].clip(0, 3);
        }
        { self[\modeY] == \random } { self[\posY] = 4.rand };
    },

    // Clock tick: advance and output
    tick: { |self, axis=\x|
        if(axis == \x) { self.advanceX } { self.advanceY };

        var cv = self[\grid][self[\posY]][self[\posX]];
        var gate = self[\gateGrid][self[\posY]][self[\posX]];

        self[\cvBus].set(cv);
        self[\gateBus].set(gate.asInteger);

        ~VISUAL_CORTEX.target.sendMsg("/rene/position",
            self[\posX], self[\posY], cv, gate.asInteger);
    },

    setCV: { |self, x, y, value|
        self[\grid][y.clip(0, 3)][x.clip(0, 3)] = value.clip(0, 1);
    },

    setGate: { |self, x, y, active|
        self[\gateGrid][y.clip(0, 3)][x.clip(0, 3)] = active;
    }
);

// ==========================================
// CAPACITIVE_GRID — Pressure Points (Touch Controller)
// ==========================================
// Language-side touch plate simulator (4 pads)
~CAPACITIVE_GRID = (
    pads: Array.fill(4, {
        (pressure: 0.0, posX: 0.5, posY: 0.5, gate: 0,
         cvBus: nil, gateBus: nil, pressureBus: nil)
    }),

    init: { |self|
        self[\pads].do({ |pad, i|
            pad[\cvBus] = Bus.control(s, 1);
            pad[\gateBus] = Bus.control(s, 1);
            pad[\pressureBus] = Bus.control(s, 1);
            ~PATCH_BAY.registerSource(
                ("pp_cv_" ++ i).asSymbol, pad[\cvBus], \control,
                "Pressure Points pad " ++ i ++ " CV");
            ~PATCH_BAY.registerSource(
                ("pp_gate_" ++ i).asSymbol, pad[\gateBus], \control,
                "Pressure Points pad " ++ i ++ " gate");
            ~PATCH_BAY.registerSource(
                ("pp_pressure_" ++ i).asSymbol, pad[\pressureBus], \control,
                "Pressure Points pad " ++ i ++ " pressure");
        });
        "CAPACITIVE_GRID: 4 pads initialized".postln;
    },

    touch: { |self, padIdx, pressure, posX, posY|
        var pad = self[\pads][padIdx.clip(0, 3)];
        pad[\pressure] = pressure.clip(0, 1);
        pad[\posX] = posX.clip(0, 1);
        pad[\posY] = posY.clip(0, 1);
        pad[\gate] = (pressure > 0.01).asInteger;

        pad[\cvBus].set(posX);
        pad[\gateBus].set(pad[\gate]);
        pad[\pressureBus].set(pressure);
    },

    release: { |self, padIdx|
        var pad = self[\pads][padIdx.clip(0, 3)];
        pad[\pressure] = 0;
        pad[\gate] = 0;
        pad[\gateBus].set(0);
        pad[\pressureBus].set(0);
    }
);

// ==========================================
// TEMPORAL_ORACLE — TEMPI (Clock Module)
// ==========================================
// 6 independent clock outputs with tap tempo, ratios
~TEMPORAL_ORACLE = (
    bpm: 120,
    outputs: Array.fill(6, { |i|
        (ratio: [1, 2, 3, 4, 6, 8][i], bus: nil, routine: nil, phase: 0)
    }),

    init: { |self|
        self[\outputs].do({ |out, i|
            out[\bus] = Bus.control(s, 1);
            ~PATCH_BAY.registerSource(
                ("tempi_" ++ i).asSymbol, out[\bus], \control,
                "TEMPI clock " ++ i);
        });
        "TEMPORAL_ORACLE: 6 clock outputs initialized".postln;
    },

    start: { |self|
        self[\outputs].do({ |out, i|
            if(out[\routine].notNil) { out[\routine].stop };
            out[\routine] = Routine({
                loop {
                    out[\bus].set(1);
                    (0.01).wait;
                    out[\bus].set(0);
                    (60 / self[\bpm] / out[\ratio] - 0.01).max(0.001).wait;
                };
            }).play;
        });
        "TEMPORAL_ORACLE: Clocks started at % BPM".format(self[\bpm]).postln;
    },

    stop: { |self|
        self[\outputs].do({ |out|
            if(out[\routine].notNil) { out[\routine].stop; out[\routine] = nil };
            out[\bus].set(0);
        });
    },

    setTempo: { |self, bpm|
        self[\bpm] = bpm.clip(20, 300);
    },

    setRatio: { |self, outputIdx, ratio|
        self[\outputs][outputIdx.clip(0, 5)][\ratio] = ratio.clip(0.125, 32);
    },

    // Tap tempo (record tap times, calculate average interval)
    tapTimes: List.new,
    tap: { |self|
        var now = SystemClock.seconds;
        self[\tapTimes].add(now);
        if(self[\tapTimes].size > 4) {
            self[\tapTimes].removeAt(0);
        };
        if(self[\tapTimes].size >= 2) {
            var intervals = List.new;
            (1..(self[\tapTimes].size - 1)).do({ |i|
                intervals.add(self[\tapTimes][i] - self[\tapTimes][i - 1]);
            });
            var avgInterval = intervals.sum / intervals.size;
            self[\bpm] = (60 / avgInterval).clip(20, 300);
            "TEMPORAL_ORACLE: Tap tempo = % BPM".format(self[\bpm].round(0.1)).postln;
        };
    }
);

// ==========================================
// OSC RESPONDERS
// ==========================================

// Rene
OSCdef(\rene_tick_x, { ~CARTESIAN_MAZE.tick(\x) }, "/rene/tick/x");
OSCdef(\rene_tick_y, { ~CARTESIAN_MAZE.tick(\y) }, "/rene/tick/y");
OSCdef(\rene_set_cv, { |msg|
    ~CARTESIAN_MAZE.setCV(msg[1].asInteger, msg[2].asInteger, msg[3].asFloat);
}, "/rene/set/cv");
OSCdef(\rene_set_gate, { |msg|
    ~CARTESIAN_MAZE.setGate(msg[1].asInteger, msg[2].asInteger, msg[3].asInteger > 0);
}, "/rene/set/gate");
OSCdef(\rene_mode_x, { |msg| ~CARTESIAN_MAZE[\modeX] = msg[1].asSymbol }, "/rene/mode/x");
OSCdef(\rene_mode_y, { |msg| ~CARTESIAN_MAZE[\modeY] = msg[1].asSymbol }, "/rene/mode/y");

// Pressure Points
OSCdef(\pp_touch, { |msg|
    ~CAPACITIVE_GRID.touch(msg[1].asInteger, msg[2].asFloat, msg[3].asFloat, msg[4].asFloat);
}, "/pp/touch");
OSCdef(\pp_release, { |msg|
    ~CAPACITIVE_GRID.release(msg[1].asInteger);
}, "/pp/release");

// TEMPI
OSCdef(\tempi_start, { ~TEMPORAL_ORACLE.start }, "/tempi/start");
OSCdef(\tempi_stop, { ~TEMPORAL_ORACLE.stop }, "/tempi/stop");
OSCdef(\tempi_tempo, { |msg| ~TEMPORAL_ORACLE.setTempo(msg[1].asFloat) }, "/tempi/tempo");
OSCdef(\tempi_ratio, { |msg|
    ~TEMPORAL_ORACLE.setRatio(msg[1].asInteger, msg[2].asFloat);
}, "/tempi/ratio");
OSCdef(\tempi_tap, { ~TEMPORAL_ORACLE.tap }, "/tempi/tap");

// Initialize
~CARTESIAN_MAZE.init;
~CAPACITIVE_GRID.init;
~TEMPORAL_ORACLE.init;

"--- BRAHMA: Make Noise Sequencer Clones Online ---".postln;
"  CARTESIAN_MAZE (Rene) | CAPACITIVE_GRID (Pressure Points) | TEMPORAL_ORACLE (TEMPI)".postln;
)
