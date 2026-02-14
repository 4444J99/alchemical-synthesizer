/*
  Phase 9: SCRIPTORIUM — Preset Management
  Project Save/Load, Per-Module Presets, Preset Morphing,
  Sample Browser, Undo/Redo
*/

(
// ==========================================
// PRESET MANAGEMENT SYSTEM
// ==========================================
~SCRIPTORIUM_PRESETS = (
    presetDir: Platform.userAppSupportDir +/+ "BrahmaPresets",
    modulePresets: IdentityDictionary.new,

    // ==========================================
    // INITIALIZATION
    // ==========================================
    init: { |self|
        File.mkdir(self[\presetDir]);
        File.mkdir(self[\presetDir] +/+ "projects");
        "SCRIPTORIUM PRESETS: Initialized at %".format(self[\presetDir]).postln;
    },

    // ==========================================
    // PER-MODULE PRESET SAVE/LOAD
    // ==========================================

    // Save a module's current parameter state
    // params: Dictionary of param -> value
    saveModulePreset: { |self, moduleName, presetName, params|
        var dir = self[\presetDir] +/+ moduleName.asString;
        var path, file, pairs;
        File.mkdir(dir);
        path = dir +/+ (presetName.asString ++ ".json");

        // Simple JSON serialization
        file = File(path, "w");
        file.write("{\n");
        pairs = List.new;
        params.keysValuesDo({ |k, v|
            case
            { v.isKindOf(String) } {
                pairs.add("  \"%\": \"%\"".format(k, v));
            }
            { v.isKindOf(Symbol) } {
                pairs.add("  \"%\": \"%\"".format(k, v.asString));
            }
            { v.isKindOf(Number) } {
                pairs.add("  \"%\": %".format(k, v));
            }
            { v.isKindOf(Boolean) } {
                pairs.add("  \"%\": %".format(k, v));
            }
            // Default: compile string for complex types
            {
                pairs.add("  \"%\": \"%\"".format(k, v.asCompileString));
            };
        });
        file.write(pairs.join(",\n"));
        file.write("\n}\n");
        file.close;
        "SCRIPTORIUM PRESETS: Saved '%/%'".format(moduleName, presetName).postln;
    },

    // Load a module preset — returns Dictionary or nil
    loadModulePreset: { |self, moduleName, presetName|
        var dir = self[\presetDir] +/+ moduleName.asString;
        var path = dir +/+ (presetName.asString ++ ".json");
        if(File.exists(path)) {
            var contents = File.readAllString(path);
            var dict = contents.parseJSON;
            if(dict.notNil) {
                "SCRIPTORIUM PRESETS: Loaded '%/%'".format(moduleName, presetName).postln;
                dict;
            } {
                "SCRIPTORIUM PRESETS: Failed to parse '%'".format(path).warn;
                nil;
            };
        } {
            "SCRIPTORIUM PRESETS: Preset '%/%' not found".format(moduleName, presetName).warn;
            nil;
        };
    },

    // List available presets for a module
    listPresets: { |self, moduleName|
        var dir = self[\presetDir] +/+ moduleName.asString;
        if(File.exists(dir)) {
            var files = PathName(dir).files.collect({ |f| f.fileNameWithoutExtension });
            "SCRIPTORIUM PRESETS: % presets for '%': %".format(
                files.size, moduleName, files).postln;
            files;
        } {
            "SCRIPTORIUM PRESETS: No presets directory for '%'".format(moduleName).postln;
            [];
        };
    },

    // Delete a module preset
    deleteModulePreset: { |self, moduleName, presetName|
        var dir = self[\presetDir] +/+ moduleName.asString;
        var path = dir +/+ (presetName.asString ++ ".json");
        if(File.exists(path)) {
            File.delete(path);
            "SCRIPTORIUM PRESETS: Deleted '%/%'".format(moduleName, presetName).postln;
        };
    },

    // ==========================================
    // PRESET MORPHING
    // ==========================================

    // Morph between two preset dictionaries
    // amount: 0.0 = fully presetA, 1.0 = fully presetB
    morphPresets: { |self, presetA, presetB, amount|
        var result = IdentityDictionary.new;
        var clippedAmount = amount.clip(0.0, 1.0);

        presetA.keysValuesDo({ |key, valA|
            var valB = presetB[key];
            if(valB.notNil and: { valA.isNumber and: { valB.isNumber } }) {
                // Numeric values: linear interpolation
                result[key] = valA.blend(valB, clippedAmount);
            } {
                // Non-numeric: snap at midpoint
                result[key] = if(clippedAmount < 0.5) { valA } { valB ? valA };
            };
        });

        // Include keys only in presetB
        presetB.keysValuesDo({ |key, valB|
            if(presetA[key].isNil) {
                result[key] = valB;
            };
        });

        result;
    },

    // Morph between two named presets of the same module
    morphNamedPresets: { |self, moduleName, presetNameA, presetNameB, amount|
        var pA = self.loadModulePreset(moduleName, presetNameA);
        var pB = self.loadModulePreset(moduleName, presetNameB);
        if(pA.notNil and: { pB.notNil }) {
            var result = self.morphPresets(pA, pB, amount);
            "SCRIPTORIUM PRESETS: Morphed '%' × '%' → % (% blend)".format(
                presetNameA, presetNameB, moduleName, amount.round(0.01)).postln;
            result;
        } { nil };
    },

    // ==========================================
    // PROJECT SAVE/LOAD (entire system state)
    // ==========================================

    saveProject: { |self, projectName|
        var dir = self[\presetDir] +/+ "projects";
        var path, state, file;
        File.mkdir(dir);
        path = dir +/+ (projectName.asString ++ ".brahma");
        state = IdentityDictionary.new;

        // Capture Chronos state
        if(~CHRONOS.notNil) {
            state[\chronos_tempo] = ~CHRONOS[\tempo];
            state[\chronos_playing] = ~CHRONOS[\playing];
            state[\chronos_globalSwing] = ~CHRONOS[\globalSwing];
            state[\chronos_currentScene] = ~CHRONOS[\currentScene];
            state[\chronos_numTracks] = ~CHRONOS[\numActiveTracks];
        };

        // Capture tuning state
        if(~BRAHMA_TUNING.notNil) {
            state[\tuning_rootHz] = ~BRAHMA_TUNING[\rootHz];
            state[\tuning_transpose] = ~BRAHMA_TUNING[\transpose];
        };

        // Capture patch bay state
        if(~PATCH_BAY.notNil) {
            state[\patchBay_routes] = ~PATCH_BAY.activeRoutes.size;
        };

        // Capture sync state
        if(~SCRIPTORIUM_SYNC.notNil) {
            state[\sync_midiClockRunning] = ~SCRIPTORIUM_SYNC[\midiClockRunning];
            state[\sync_linkActive] = ~SCRIPTORIUM_SYNC[\linkClock].notNil;
        };

        // Serialize as SC compile string (safe for re-interpretation)
        file = File(path, "w");
        file.write(state.asCompileString);
        file.close;
        "SCRIPTORIUM PRESETS: Project '%' saved → %".format(projectName, path).postln;
    },

    loadProject: { |self, projectName|
        var dir = self[\presetDir] +/+ "projects";
        var path = dir +/+ (projectName.asString ++ ".brahma");
        if(File.exists(path)) {
            var contents = File.readAllString(path);
            var state = contents.interpret;
            if(state.notNil) {
                // Restore Chronos
                if(state[\chronos_tempo].notNil and: { ~CHRONOS.notNil }) {
                    ~CHRONOS[\tempo] = state[\chronos_tempo];
                    ~CHRONOS[\globalSwing] = state[\chronos_globalSwing] ? 0.0;
                };

                // Restore tuning
                if(state[\tuning_rootHz].notNil and: { ~BRAHMA_TUNING.notNil }) {
                    ~BRAHMA_TUNING[\rootHz] = state[\tuning_rootHz];
                    ~BRAHMA_TUNING[\transpose] = state[\tuning_transpose] ? 0;
                };

                "SCRIPTORIUM PRESETS: Project '%' loaded".format(projectName).postln;
                state;
            } {
                "SCRIPTORIUM PRESETS: Failed to interpret project '%'".format(projectName).warn;
                nil;
            };
        } {
            "SCRIPTORIUM PRESETS: Project '%' not found".format(projectName).warn;
            nil;
        };
    },

    listProjects: { |self|
        var dir = self[\presetDir] +/+ "projects";
        if(File.exists(dir)) {
            var files = PathName(dir).files.select({ |f|
                f.extension == "brahma";
            }).collect({ |f| f.fileNameWithoutExtension });
            "SCRIPTORIUM PRESETS: Projects: %".format(files).postln;
            files;
        } { [] };
    },

    deleteProject: { |self, projectName|
        var dir = self[\presetDir] +/+ "projects";
        var path = dir +/+ (projectName.asString ++ ".brahma");
        if(File.exists(path)) {
            File.delete(path);
            "SCRIPTORIUM PRESETS: Project '%' deleted".format(projectName).postln;
        };
    }
);

// Initialize preset system
~SCRIPTORIUM_PRESETS.init;

// ==========================================
// UNDO/REDO SYSTEM (Global Scope)
// ==========================================
~SCRIPTORIUM_UNDO = (
    snapshots: List.new,
    position: -1,
    maxSnapshots: 32,

    // ==========================================
    // SNAPSHOT CAPTURE
    // ==========================================

    capture: { |self, label|
        var state;

        // Discard any future states (branch point after undo)
        while { self[\snapshots].size > (self[\position] + 1) } {
            self[\snapshots].pop;
        };

        state = IdentityDictionary.new;
        state[\label] = label;
        state[\timestamp] = Main.elapsedTime;

        // Capture Chronos tempo and swing
        if(~CHRONOS.notNil) {
            state[\chronos_tempo] = ~CHRONOS[\tempo];
            state[\chronos_globalSwing] = ~CHRONOS[\globalSwing];
        };

        // Capture patch bay connections (deep copy)
        if(~PATCH_BAY.notNil) {
            state[\patchBay_routes] = ~PATCH_BAY.activeRoutes.deepCopy;
        };

        // Capture tuning
        if(~BRAHMA_TUNING.notNil) {
            state[\tuning_rootHz] = ~BRAHMA_TUNING[\rootHz];
            state[\tuning_transpose] = ~BRAHMA_TUNING[\transpose];
        };

        self[\snapshots].add(state);

        // Enforce max snapshot limit
        if(self[\snapshots].size > self[\maxSnapshots]) {
            self[\snapshots].removeAt(0);
        };

        self[\position] = self[\snapshots].size - 1;
        "SCRIPTORIUM UNDO: Captured '%' (% of % slots)".format(
            label, self[\position] + 1, self[\maxSnapshots]).postln;
    },

    // ==========================================
    // UNDO
    // ==========================================

    undo: { |self|
        if(self[\position] > 0) {
            self[\position] = self[\position] - 1;

            var state = self[\snapshots][self[\position]];

            // Restore Chronos
            if(state[\chronos_tempo].notNil and: { ~CHRONOS.notNil }) {
                ~CHRONOS[\tempo] = state[\chronos_tempo];
                ~CHRONOS[\globalSwing] = state[\chronos_globalSwing] ? 0.0;
            };

            // Restore tuning
            if(state[\tuning_rootHz].notNil and: { ~BRAHMA_TUNING.notNil }) {
                ~BRAHMA_TUNING[\rootHz] = state[\tuning_rootHz];
                ~BRAHMA_TUNING[\transpose] = state[\tuning_transpose] ? 0;
            };

            "SCRIPTORIUM UNDO: Undo → '%' (position %)".format(
                state[\label], self[\position]).postln;
            state;
        } {
            "SCRIPTORIUM UNDO: Nothing to undo".postln;
            nil;
        };
    },

    // ==========================================
    // REDO
    // ==========================================

    redo: { |self|
        if(self[\position] < (self[\snapshots].size - 1)) {
            self[\position] = self[\position] + 1;

            var state = self[\snapshots][self[\position]];

            // Restore Chronos
            if(state[\chronos_tempo].notNil and: { ~CHRONOS.notNil }) {
                ~CHRONOS[\tempo] = state[\chronos_tempo];
                ~CHRONOS[\globalSwing] = state[\chronos_globalSwing] ? 0.0;
            };

            // Restore tuning
            if(state[\tuning_rootHz].notNil and: { ~BRAHMA_TUNING.notNil }) {
                ~BRAHMA_TUNING[\rootHz] = state[\tuning_rootHz];
                ~BRAHMA_TUNING[\transpose] = state[\tuning_transpose] ? 0;
            };

            "SCRIPTORIUM UNDO: Redo → '%' (position %)".format(
                state[\label], self[\position]).postln;
            state;
        } {
            "SCRIPTORIUM UNDO: Nothing to redo".postln;
            nil;
        };
    },

    // ==========================================
    // STATUS / HISTORY
    // ==========================================

    status: { |self|
        "SCRIPTORIUM UNDO STATUS:".postln;
        "  Snapshots: % / %".format(self[\snapshots].size, self[\maxSnapshots]).postln;
        "  Position: %".format(self[\position]).postln;
        "  Can undo: %".format(self[\position] > 0).postln;
        "  Can redo: %".format(self[\position] < (self[\snapshots].size - 1)).postln;
        if(self[\snapshots].size > 0) {
            "  History:".postln;
            self[\snapshots].do({ |snap, i|
                var marker = if(i == self[\position]) { " <<" } { "" };
                "    [%] '%'%".format(i, snap[\label], marker).postln;
            });
        };
    },

    clear: { |self|
        self[\snapshots] = List.new;
        self[\position] = -1;
        "SCRIPTORIUM UNDO: History cleared".postln;
    }
);

// ==========================================
// OSC RESPONDERS — PRESETS
// ==========================================

// /scriptorium/preset/save <module:string> <name:string> [param1:string] [val1:float] ...
OSCdef(\scriptorium_preset_save, { |msg|
    var moduleName = msg[1].asString;
    var presetName = msg[2].asString;
    var params = IdentityDictionary.new;
    var idx = 3;

    // Parse key-value pairs from remaining OSC args
    while { idx < (msg.size - 1) } {
        var key = msg[idx].asString.asSymbol;
        var val = msg[idx + 1];
        // Attempt numeric conversion; fall back to string
        if(val.isKindOf(Number)) {
            params[key] = val.asFloat;
        } {
            params[key] = val.asString;
        };
        idx = idx + 2;
    };

    ~SCRIPTORIUM_PRESETS.saveModulePreset(moduleName, presetName, params);
}, "/scriptorium/preset/save");

// /scriptorium/preset/load <module:string> <name:string>
OSCdef(\scriptorium_preset_load, { |msg|
    var moduleName = msg[1].asString;
    var presetName = msg[2].asString;
    var preset = ~SCRIPTORIUM_PRESETS.loadModulePreset(moduleName, presetName);

    // Broadcast loaded preset to Visual Cortex
    if(preset.notNil and: { ~VISUAL_CORTEX.notNil }) {
        ~VISUAL_CORTEX[\target].sendMsg(
            "/brahma/preset/loaded", moduleName, presetName);
    };
}, "/scriptorium/preset/load");

// /scriptorium/preset/list <module:string>
OSCdef(\scriptorium_preset_list, { |msg|
    var moduleName = msg[1].asString;
    var presets = ~SCRIPTORIUM_PRESETS.listPresets(moduleName);

    // Broadcast list to Visual Cortex
    if(~VISUAL_CORTEX.notNil) {
        presets.do({ |name|
            ~VISUAL_CORTEX[\target].sendMsg(
                "/brahma/preset/item", moduleName, name);
        });
    };
}, "/scriptorium/preset/list");

// /scriptorium/preset/delete <module:string> <name:string>
OSCdef(\scriptorium_preset_delete, { |msg|
    ~SCRIPTORIUM_PRESETS.deleteModulePreset(msg[1].asString, msg[2].asString);
}, "/scriptorium/preset/delete");

// /scriptorium/preset/morph <module:string> <presetA:string> <presetB:string> <amount:float>
OSCdef(\scriptorium_preset_morph, { |msg|
    var moduleName = msg[1].asString;
    var presetA = msg[2].asString;
    var presetB = msg[3].asString;
    var amount = msg[4].asFloat;
    ~SCRIPTORIUM_PRESETS.morphNamedPresets(moduleName, presetA, presetB, amount);
}, "/scriptorium/preset/morph");

// ==========================================
// OSC RESPONDERS — PROJECT
// ==========================================

// /scriptorium/project/save <name:string>
OSCdef(\scriptorium_project_save, { |msg|
    ~SCRIPTORIUM_PRESETS.saveProject(msg[1].asString);
}, "/scriptorium/project/save");

// /scriptorium/project/load <name:string>
OSCdef(\scriptorium_project_load, { |msg|
    ~SCRIPTORIUM_PRESETS.loadProject(msg[1].asString);
}, "/scriptorium/project/load");

// /scriptorium/project/list
OSCdef(\scriptorium_project_list, {
    var projects = ~SCRIPTORIUM_PRESETS.listProjects;
    if(~VISUAL_CORTEX.notNil) {
        projects.do({ |name|
            ~VISUAL_CORTEX[\target].sendMsg("/brahma/project/item", name);
        });
    };
}, "/scriptorium/project/list");

// /scriptorium/project/delete <name:string>
OSCdef(\scriptorium_project_delete, { |msg|
    ~SCRIPTORIUM_PRESETS.deleteProject(msg[1].asString);
}, "/scriptorium/project/delete");

// ==========================================
// OSC RESPONDERS — UNDO/REDO
// ==========================================

// /scriptorium/undo/capture [label:string]
OSCdef(\scriptorium_undo_capture, { |msg|
    var label = msg[1] !? _.asString ?? "manual snapshot";
    ~SCRIPTORIUM_UNDO.capture(label);
}, "/scriptorium/undo/capture");

// /scriptorium/undo
OSCdef(\scriptorium_undo, {
    ~SCRIPTORIUM_UNDO.undo;
}, "/scriptorium/undo");

// /scriptorium/redo
OSCdef(\scriptorium_redo, {
    ~SCRIPTORIUM_UNDO.redo;
}, "/scriptorium/redo");

// /scriptorium/undo/status
OSCdef(\scriptorium_undo_status, {
    ~SCRIPTORIUM_UNDO.status;
}, "/scriptorium/undo/status");

// /scriptorium/undo/clear
OSCdef(\scriptorium_undo_clear, {
    ~SCRIPTORIUM_UNDO.clear;
}, "/scriptorium/undo/clear");

"--- BRAHMA: SCRIPTORIUM Preset Management Online ---".postln;
)
