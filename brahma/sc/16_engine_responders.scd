/*
  Tier 1: VOICE — Polyphonic Engine Voice Manager
  OSC-driven note allocation for synthesis engines.
  Supports microtonal frequencies via ~BRAHMA_TUNING, per-voice parameter setting,
  and max 16 voices per instance.
*/

(
~ENGINE_VOICES = IdentityDictionary.new;

// ==========================================
// VOICE MANAGEMENT HELPERS
// ==========================================

// Create or get a voice instance container
~engineVoiceGetInstance = { |instanceName, engineName|
    if(~ENGINE_VOICES[instanceName.asSymbol].isNil) {
        ~ENGINE_VOICES[instanceName.asSymbol] = (
            voices: IdentityDictionary.new, // note -> Synth
            params: IdentityDictionary.new, // extra params
            outBus: 0,
            engineName: engineName.asSymbol
        );
    };
    ~ENGINE_VOICES[instanceName.asSymbol];
};

// ==========================================
// OSC: Note On
// /brahma/engine/noteOn <engine> <instance> <note> <velocity> [param val ...]
// ==========================================
OSCdef(\engine_noteOn, { |msg|
    var engineName = msg[1].asSymbol;
    var instanceName = msg[2].asSymbol;
    var note = msg[3].asInteger;
    var vel = msg[4].asFloat;
    var inst = ~engineVoiceGetInstance.(instanceName, engineName);
    var spec = ~MODULE_REGISTRY.getSpec(engineName);

    if(spec.notNil) {
        var freq, args, i, synth;

        // Enforce max 16 voices
        if(inst[\voices].size >= 16) {
            var oldestKey = inst[\voices].keys.asArray.sort.first;
            if(oldestKey.notNil) {
                inst[\voices][oldestKey].set(\gate, 0);
                inst[\voices].removeAt(oldestKey);
            };
        };

        // Convert MIDI note to frequency using microtonal system if available
        freq = if(~BRAHMA_TUNING.notNil and: { ~BRAHMA_TUNING[\degreeToFreq].notNil }) {
            ~BRAHMA_TUNING.degreeToFreq(note);
        } {
            note.midicps;
        };

        // Build synth args
        args = [\freq, freq, \gate, 1, \velocity, vel, \outBus, inst[\outBus]];

        // Apply stored instance params
        inst[\params].keysValuesDo({ |k, v|
            args = args ++ [k, v];
        });

        // Apply inline param overrides (pairs after velocity)
        i = 5;
        while({ i < (msg.size - 1) }) {
            args = args ++ [msg[i].asSymbol, msg[i+1].asFloat];
            i = i + 2;
        };

        synth = Synth(spec[\synthDef], args, spec[\group], \addToTail);
        inst[\voices][note] = synth;
    } {
        "ENGINE_VOICES: Unknown engine '%'".format(engineName).postln;
    };
}, "/brahma/engine/noteOn");

// ==========================================
// OSC: Note Off
// /brahma/engine/noteOff <instance> <note>
// ==========================================
OSCdef(\engine_noteOff, { |msg|
    var instanceName = msg[1].asSymbol;
    var note = msg[2].asInteger;
    var inst = ~ENGINE_VOICES[instanceName];

    if(inst.notNil) {
        var synth = inst[\voices][note];
        if(synth.notNil) {
            synth.set(\gate, 0);
            inst[\voices].removeAt(note);
        };
    };
}, "/brahma/engine/noteOff");

// ==========================================
// OSC: Set param on all active voices of an instance
// /brahma/engine/set <instance> <param> <value>
// ==========================================
OSCdef(\engine_set, { |msg|
    var instanceName = msg[1].asSymbol;
    var param = msg[2].asSymbol;
    var value = msg[3].asFloat;
    var inst = ~ENGINE_VOICES[instanceName];

    if(inst.notNil) {
        // Store for future voices
        inst[\params][param] = value;
        // Set on all active voices
        inst[\voices].do({ |synth|
            synth.set(param, value);
        });
    };
}, "/brahma/engine/set");

// ==========================================
// OSC: Set output bus for an instance
// /brahma/engine/setOutBus <instance> <bus>
// ==========================================
OSCdef(\engine_setOutBus, { |msg|
    var instanceName = msg[1].asSymbol;
    var bus = msg[2].asInteger;
    var inst = ~ENGINE_VOICES[instanceName];

    if(inst.notNil) {
        inst[\outBus] = bus;
        inst[\voices].do({ |synth|
            synth.set(\outBus, bus);
        });
    };
}, "/brahma/engine/setOutBus");

// ==========================================
// OSC: Free all voices of an instance
// /brahma/engine/freeAll <instance>
// ==========================================
OSCdef(\engine_freeAll, { |msg|
    var instanceName = msg[1].asSymbol;
    var inst = ~ENGINE_VOICES[instanceName];

    if(inst.notNil) {
        inst[\voices].do({ |synth| synth.free });
        inst[\voices] = IdentityDictionary.new;
        "ENGINE_VOICES: Freed all voices for '%'".format(instanceName).postln;
    };
}, "/brahma/engine/freeAll");

"--- BRAHMA: Engine Voice Manager Online ---".postln;
)
