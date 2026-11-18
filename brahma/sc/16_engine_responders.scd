/*
  Tier 1: VOICE — Polyphonic Engine Voice Manager
  OSC-driven note allocation for synthesis engines.
  Supports microtonal frequencies via ~brahma_tuning, per-voice parameter setting,
  and max 16 voices per instance.
*/

(
~engine_voices = IdentityDictionary.new;

// ==========================================
// VOICE MANAGEMENT HELPERS
// ==========================================

// Create or get a voice instance container
~engineVoiceGetInstance = { |instanceName, engineName|
    if(~engine_voices[instanceName.asSymbol].isNil) {
        ~engine_voices[instanceName.asSymbol] = (
            voices: IdentityDictionary.new, // note -> Synth
            activeNodes: List.new, // includes release tails, in creation order
            params: IdentityDictionary.new, // extra params
            outBus: 0,
            engineName: engineName.asSymbol
        );
    };
    ~engine_voices[instanceName.asSymbol];
};

// Keep release tails reachable until /n_end, so panic can stop every node.
~engineVoiceFreeAll = { |inst|
    var count = inst[\activeNodes].size;
    inst[\activeNodes].do(_.free);
    inst[\activeNodes] = List.new;
    inst[\voices] = IdentityDictionary.new;
    count
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
    var spec = ~module_registry.getSpec(engineName);

    if(spec.notNil) {
        var freq, args, i, synth, previous;

        // Retriggering a held note releases its previous node before replacing
        // the lookup. Its release tail remains in activeNodes until /n_end.
        previous = inst[\voices][note];
        if(previous.notNil) {
            previous.set(\gate, 0);
            inst[\voices].removeAt(note);
        };

        // Bound all allocated voices, including release tails. Steal the
        // oldest node, not the lowest MIDI note.
        if(inst[\activeNodes].size >= 16) {
            var oldest = inst[\activeNodes].removeAt(0);
            inst[\voices].keys.asArray.do { |key|
                if(inst[\voices][key] === oldest) { inst[\voices].removeAt(key) };
            };
            oldest.free;
        };

        // Convert MIDI note to frequency using microtonal system if available
        freq = if(~brahma_tuning.notNil and: { ~brahma_tuning[\degreeToFreq].notNil }) {
            ~brahma_tuning.degreeToFreq(note);
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
        inst[\activeNodes].add(synth);
        synth.onFree {
            inst[\activeNodes].remove(synth);
            if(inst[\voices][note] === synth) { inst[\voices].removeAt(note) };
        };
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
    var inst = ~engine_voices[instanceName];

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
    var inst = ~engine_voices[instanceName];

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
    var inst = ~engine_voices[instanceName];

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
    var inst = ~engine_voices[instanceName];

    if(inst.notNil) {
        ~engineVoiceFreeAll.(inst);
        "ENGINE_VOICES: Freed all voices for '%'".format(instanceName).postln;
    };
}, "/brahma/engine/freeAll");

// ==========================================
// OSC: Foundry render request (issue #96)
// /brahma/foundry/render <renderId> <module> <durationSec> <outputPath>
//
// Renders one module voice to a WAV with the headless NRT renderer and
// reports completion back to the Foundry. This lives here, not in
// 13_nrt_renderer.scd: 13 is headless-only (driven from sclang/bounce.sh,
// its renderSpecimen needs an input file), while this file owns live OSC
// dispatch and the module registry lookup. The NRT score below follows
// 13's recordNRT pattern (WAV int16, 44100 Hz, stereo).
//
// Every outcome gets a reply — the Foundry's ack discipline from #119:
//   /brahma/foundry/render/done   <renderId> "ok" <outputPath>
//   /brahma/foundry/render/failed <renderId> <reason>
// A dispatch is not a completion: the Foundry only trusts a file it can
// measure itself. Replies go to the Foundry bridge via ~visual_cortex.target
// (127.0.0.1:57122), the same path the instrument-note acks use.
// ==========================================
OSCdef(\foundry_render, { |msg|
    var renderId, moduleName, duration, outputPath, spec, desc, defBytes;
    var score, opts, oscFile, target;
    renderId = msg[1].asString;
    moduleName = msg[2].asString;
    duration = msg[3].asFloat;
    outputPath = msg[4].asString;
    target = ~visual_cortex.target;

    if(target.isNil) {
        "FOUNDRY_RENDER: no visual-cortex target, cannot reply".postln;
    } {
        if(renderId.isNil or: { renderId.size == 0 }) {
            // No renderId the Foundry can match: nothing to reply to.
            "FOUNDRY_RENDER: missing renderId".postln;
        } {
            if(moduleName.isNil or: { moduleName.size == 0 }) {
                target.sendMsg("/brahma/foundry/render/failed", renderId, "missing module");
            } {
                spec = ~module_registry.getSpec(moduleName.asSymbol);
                if(spec.isNil) {
                    target.sendMsg("/brahma/foundry/render/failed", renderId, "unknown module: " ++ moduleName);
                } {
                    if(duration.isNil or: { duration <= 0 } or: { duration > 60 }) {
                        target.sendMsg("/brahma/foundry/render/failed", renderId, "durationSec out of range (0, 60]");
                    } {
                        if(outputPath.isNil or: { outputPath.size == 0 } or: { outputPath.endsWith(".wav").not }) {
                            target.sendMsg("/brahma/foundry/render/failed", renderId, "outputPath must be a .wav path");
                        } {
                            desc = SynthDescLib.global.at(spec[\synthDef]);
                            if(desc.isNil or: { desc.def.isNil }) {
                                target.sendMsg("/brahma/foundry/render/failed", renderId, "module synthdef unavailable: " ++ moduleName);
                            } {
                                defBytes = desc.def.asBytes;
                                oscFile = outputPath ++ ".osc";
                                score = Score([
                                    [0.0, [\d_recv, defBytes]],
                                    [0.0, [\s_new, spec[\synthDef], 1000, 0, 0,
                                        \freq, 440, \gate, 1, \velocity, 0.8, \outBus, 0]],
                                    [duration, [\n_set, 1000, \gate, 0]],
                                    [duration + 0.5, [\c_set, 0, 0]]
                                ]);
                                opts = ServerOptions.new
                                    .numOutputBusChannels_(2)
                                    .numInputBusChannels_(0)
                                    .sampleRate_(44100);
                                ("FOUNDRY_RENDER: " ++ moduleName ++ " -> " ++ outputPath
                                    ++ " (" ++ duration ++ "s)").postln;
                                score.recordNRT(
                                    oscFilePath: oscFile,
                                    outputFilePath: outputPath,
                                    sampleRate: 44100,
                                    headerFormat: "WAV",
                                    sampleFormat: "int16",
                                    options: opts,
                                    duration: duration + 1.0,
                                    action: { |exitCode|
                                        if(exitCode == 0) {
                                            target.sendMsg("/brahma/foundry/render/done",
                                                renderId, "ok", outputPath);
                                        } {
                                            target.sendMsg("/brahma/foundry/render/failed",
                                                renderId, "nrt exit " ++ exitCode);
                                        };
                                    }
                                );
                            };
                        };
                    };
                };
            };
        };
    };
}, "/brahma/foundry/render");

"--- BRAHMA: Engine Voice Manager Online ---".postln;
)
