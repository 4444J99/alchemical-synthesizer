/*
  Phase 1: CHRONOS — The Master Sequencer
  Core state machine, transport, global state

  Named after the Titan primordial god of Time.
  Chronos devours and regenerates, perfectly mirroring
  a sequencer that cycles, mutates, and drives all organisms.
*/

(
// ==========================================
// CHRONOS CORE STATE
// ==========================================
~CHRONOS = (
    // Transport state
    playing: false,
    recording: false,
    tempo: 120,
    clock: nil,

    // Track management
    tracks: Array.new(128),  // Dynamically allocated
    numActiveTracks: 0,
    maxTracks: 128,

    // Song mode
    songMode: false,
    songChain: List.new,    // List of (patternIdx, loopCount, condition)
    songPosition: 0,

    // Scene system (8 scenes)
    scenes: Array.fill(8, { nil }),
    currentScene: 0,
    morphAmount: 0.0,       // 0.0 = scene A, 1.0 = scene B
    morphSourceScene: 0,
    morphTargetScene: 1,

    // Undo/Redo (32 levels)
    undoStack: List.new,
    redoStack: List.new,
    maxUndoLevels: 32,

    // Fill state
    fillActive: false,

    // Registered targets (organisms/synths that Chronos can trigger)
    targets: Dictionary.new,

    // Global swing
    globalSwing: 0.0,

    // ==========================================
    // TARGET REGISTRATION
    // ==========================================
    // Organisms register themselves as triggerable targets
    registerTarget: { |self, name, synthDef, outBus, group|
        self[\targets].put(name.asSymbol, (
            synthDef: synthDef,
            outBus: outBus,
            group: group ? ~SC_GRP[\te]
        ));
        "CHRONOS: Target '%' registered (%)".format(name, synthDef).postln;
    },

    unregisterTarget: { |self, name|
        self[\targets].removeAt(name.asSymbol);
    },

    // ==========================================
    // UNDO/REDO
    // ==========================================
    pushUndoState: { |self|
        var snapshot = self[\tracks].collect({ |t|
            if(t.notNil) { t.deepCopy } { nil };
        });
        self[\undoStack].add(snapshot);
        if(self[\undoStack].size > self[\maxUndoLevels]) {
            self[\undoStack].removeAt(0);
        };
        // Clear redo on new action
        self[\redoStack] = List.new;
    },

    undo: { |self|
        if(self[\undoStack].size > 0) {
            var current, prev;
            // Save current state to redo
            current = self[\tracks].collect({ |t|
                if(t.notNil) { t.deepCopy } { nil };
            });
            self[\redoStack].add(current);

            // Restore previous state
            prev = self[\undoStack].pop;
            prev.do({ |t, i|
                if(t.notNil and: { i < self[\tracks].size }) {
                    self[\tracks][i] = t;
                };
            });
            "CHRONOS: Undo (% levels remaining)".format(self[\undoStack].size).postln;
        };
    },

    redo: { |self|
        if(self[\redoStack].size > 0) {
            var current, next;
            current = self[\tracks].collect({ |t|
                if(t.notNil) { t.deepCopy } { nil };
            });
            self[\undoStack].add(current);

            next = self[\redoStack].pop;
            next.do({ |t, i|
                if(t.notNil and: { i < self[\tracks].size }) {
                    self[\tracks][i] = t;
                };
            });
            "CHRONOS: Redo (% levels remaining)".format(self[\redoStack].size).postln;
        };
    },

    // ==========================================
    // SCENE SYSTEM
    // ==========================================
    saveScene: { |self, sceneIdx|
        sceneIdx = sceneIdx.clip(0, 7);
        self[\scenes][sceneIdx] = self[\tracks].collect({ |t|
            if(t.notNil) { t.deepCopy } { nil };
        });
        "CHRONOS: Scene % saved".format(sceneIdx).postln;
    },

    loadScene: { |self, sceneIdx|
        sceneIdx = sceneIdx.clip(0, 7);
        if(self[\scenes][sceneIdx].notNil) {
            self.pushUndoState;
            self[\scenes][sceneIdx].do({ |t, i|
                if(t.notNil and: { i < self[\tracks].size }) {
                    self[\tracks][i] = t.deepCopy;
                };
            });
            self[\currentScene] = sceneIdx;
            "CHRONOS: Scene % loaded".format(sceneIdx).postln;
        };
    },

    // Morph between two scenes (0.0 = source, 1.0 = target)
    morphScenes: { |self, amount|
        var srcScene = self[\scenes][self[\morphSourceScene]];
        var dstScene = self[\scenes][self[\morphTargetScene]];

        if(srcScene.notNil and: { dstScene.notNil }) {
            self[\morphAmount] = amount.clip(0.0, 1.0);
            // Interpolate numeric parameters between scenes
            self[\tracks].do({ |track, i|
                if(track.notNil and: { srcScene[i].notNil } and: { dstScene[i].notNil }) {
                    var src = srcScene[i];
                    var dst = dstScene[i];

                    // Morph synth args (numeric values only)
                    track[\synthArgs].keysValuesDo({ |k, v|
                        if(v.isKindOf(Number) and: { src[\synthArgs][k].notNil } and: { dst[\synthArgs][k].notNil }) {
                            track[\synthArgs][k] = src[\synthArgs][k].blend(
                                dst[\synthArgs][k], amount);
                        };
                    });
                };
            });
        };
    },

    // ==========================================
    // SONG MODE
    // ==========================================
    addSongEntry: { |self, sceneIdx, loopCount=1, condition=\always|
        self[\songChain].add((
            sceneIdx: sceneIdx,
            loopCount: loopCount,
            condition: condition.asSymbol  // \always, \onFill, \notFill
        ));
    },

    clearSong: { |self|
        self[\songChain] = List.new;
        self[\songPosition] = 0;
    },

    advanceSong: { |self|
        if(self[\songMode] and: { self[\songChain].size > 0 }) {
            var entry, shouldAdvance, nextEntry;
            entry = self[\songChain][self[\songPosition] % self[\songChain].size];
            shouldAdvance = true;

            // Check condition
            case
            { entry[\condition] == \onFill } { shouldAdvance = self[\fillActive] }
            { entry[\condition] == \notFill } { shouldAdvance = self[\fillActive].not };

            if(shouldAdvance) {
                self[\songPosition] = self[\songPosition] + 1;
                if(self[\songPosition] < self[\songChain].size) {
                    nextEntry = self[\songChain][self[\songPosition]];
                    self.loadScene(nextEntry[\sceneIdx]);
                } {
                    // Song complete — loop or stop
                    self[\songPosition] = 0;
                };
            };
        };
    }
);

"--- BRAHMA: CHRONOS Core State Initialized ---".postln;
)
