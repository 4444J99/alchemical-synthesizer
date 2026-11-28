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

// ==========================================
// OSC: Testament sonic bridge receiver (issue #127)
// /testament/master <amp>
// /testament/bpm <bpm>
// /testament/env <attack> <decay> <sustain> <release>
// /testament/filter <cutoff> <resonance>
// /testament/voice/N <freq> <amp> <waveform> <detune> <pan>
//
// The engine half (organvm-engine#49) renders the system's sonic
// self-portrait and transmits it as OSC 1.0 over UDP to 127.0.0.1:57120
// (one bundle with an immediate timetag, or per-message datagrams;
// sclang dispatches bundle elements individually, so both forms arrive
// here identically). This section is the listening half: it sounds the
// portrait through one oscillator voice per organ index.
//
// Deviations from the engine's docstring, on live evidence: the engine
// names a TestamentReceiver.sc class file, but this repo's receivers are
// OSCdefs in responder .scd files (this file already owns
// /brahma/foundry/render the same way), so the receiver lives here and
// needs no loader change — loader.scd already loads this file inside
// s.doWhenBooted. The engine bridge is fire-and-forget (no receive path
// in osc_bridge.py), so there is no ack surface to reply on: outcomes are
// posted to the SC post window, and bad args are typed postln warnings,
// never a silent no-op. bpm drives the shared Chronos clock when it
// exists (~chronos.setTempo, the same call its own
// /chronos/transport/tempo responder makes); without Chronos the value is
// stored, not pretended. The wire carries no filter type (the renderer
// always sends lowpass), so the voice is lowpass by construction.
// ==========================================
~testament = (
    master: 0.5,
    attack: 0.01, decay: 0.5, sustain: 0.7, release: 0.3,
    cutoff: 8000, resonance: 0.0, bpm: 120,
    voices: IdentityDictionary.new, // index -> Synth
    maxVoices: 16
);

// One oscillator voice per organ. Waveform is an index (0 sine, 1 saw,
// 2 square, 3 tri) so the SynthDef never parses strings; detune is in
// cents, as the engine sends it. The filter is lowpass by construction
// (the wire carries no type). master is a separate multiplier so a
// /testament/master message retunes live voices without re-voicing them.
SynthDef(\testament_voice, { |freq=440, amp=0.2, wave=0, detune=0, pan=0,
    attack=0.01, decay=0.5, sustain=0.7, release=0.3,
    cutoff=8000, resonance=0, master=1, gate=1, out=0|
    var detuned, sig, filtered, env;
    detuned = freq * (2 ** (detune.clip(-100, 100) / 1200));
    sig = Select.ar(wave.clip(0, 3), [
        SinOsc.ar(detuned),
        Saw.ar(detuned),
        Pulse.ar(detuned, 0.5),
        LFTri.ar(detuned)
    ]);
    filtered = RLPF.ar(sig, cutoff.clip(20, 20000),
        (1 - resonance.clip(0, 1)).clip(0.05, 1));
    env = Env.adsr(attack.clip(0.001, 10), decay.clip(0.001, 10),
        sustain.clip(0, 1), release.clip(0.01, 10));
    sig = filtered * EnvGen.kr(env, gate, doneAction: 2);
    Out.ar(out, Pan2.ar(sig, pan.clip(-1, 1), amp.clip(0, 1) * master.clip(0, 1)));
}).add;

// Waveform string -> voice index. Unknown names fall back to sine and say
// so: silently playing a different timbre than the portrait asked for
// would hide a broken mapping.
~testamentWaveIndex = { |waveform|
    var w = waveform.asString;
    if(w == "saw") { 1 } {
        if(w == "square") { 2 } {
            if(w == "tri") { 3 } {
                if(w != "sine") {
                    "TESTAMENT: unknown waveform '%' — using sine".format(w).postln;
                };
                0
            }
        }
    }
};

// Trigger (or retrigger) one voice index. Retriggering gates the previous
// node off first — its release tail plays out, then /n_end frees it —
// so a new portrait never leaves hanging duplicates behind.
~testamentVoiceTrigger = { |index, freq, amp, wave, detune, pan|
    var previous, synth;
    previous = ~testament[\voices][index];
    if(previous.notNil) {
        previous.set(\gate, 0);
        ~testament[\voices].removeAt(index);
    };
    synth = Synth(\testament_voice, [
        \freq, freq.clip(20, 20000),
        \amp, amp.clip(0, 1),
        \wave, ~testamentWaveIndex.(wave),
        \detune, detune.clip(-100, 100),
        \pan, pan.clip(-1, 1),
        \attack, ~testament[\attack], \decay, ~testament[\decay],
        \sustain, ~testament[\sustain], \release, ~testament[\release],
        \cutoff, ~testament[\cutoff], \resonance, ~testament[\resonance],
        \master, ~testament[\master],
        \gate, 1, \out, 0
    ]);
    ~testament[\voices][index] = synth;
    synth.onFree {
        if(~testament[\voices][index] === synth) { ~testament[\voices].removeAt(index) };
    };
    synth
};

// Free every testament voice (operator/console use; the engine sends no
// stop message — a new portrait replaces voices index by index).
~testamentFreeAll = {
    var count = 0;
    ~testament[\voices].keysValuesDo({ |index, synth|
        synth.set(\gate, 0);
        count = count + 1;
    });
    ~testament[\voices] = IdentityDictionary.new;
    count
};

OSCdef(\testament_master, { |msg|
    var master;
    if(msg.size < 2) {
        "TESTAMENT: bad_args: /testament/master needs <amp>".postln;
    } {
        master = msg[1].asFloat.clip(0, 1);
        ~testament[\master] = master;
        ~testament[\voices].do({ |synth| synth.set(\master, master) });
        ("TESTAMENT: master " ++ master).postln;
    };
}, "/testament/master");

OSCdef(\testament_bpm, { |msg|
    var bpm;
    if(msg.size < 2) {
        "TESTAMENT: bad_args: /testament/bpm needs <bpm>".postln;
    } {
        bpm = msg[1].asFloat.clip(20, 300);
        ~testament[\bpm] = bpm;
        if(~chronos.notNil and: { ~chronos[\setTempo].notNil }) {
            ~chronos.setTempo(bpm);
        } {
            "TESTAMENT: bpm % (no Chronos clock to drive)".format(bpm).postln;
        };
    };
}, "/testament/bpm");

OSCdef(\testament_env, { |msg|
    if(msg.size < 5) {
        "TESTAMENT: bad_args: /testament/env needs <attack> <decay> <sustain> <release>".postln;
    } {
        ~testament[\attack] = msg[1].asFloat.clip(0.001, 10);
        ~testament[\decay] = msg[2].asFloat.clip(0.001, 10);
        ~testament[\sustain] = msg[3].asFloat.clip(0, 1);
        ~testament[\release] = msg[4].asFloat.clip(0.01, 10);
        ~testament[\voices].do({ |synth|
            synth.set(\attack, ~testament[\attack], \decay, ~testament[\decay],
                \sustain, ~testament[\sustain], \release, ~testament[\release]);
        });
        "TESTAMENT: env set".postln;
    };
}, "/testament/env");

OSCdef(\testament_filter, { |msg|
    if(msg.size < 3) {
        "TESTAMENT: bad_args: /testament/filter needs <cutoff> <resonance>".postln;
    } {
        ~testament[\cutoff] = msg[1].asFloat.clip(20, 20000);
        ~testament[\resonance] = msg[2].asFloat.clip(0, 1);
        ~testament[\voices].do({ |synth|
            synth.set(\cutoff, ~testament[\cutoff], \resonance, ~testament[\resonance]);
        });
        "TESTAMENT: filter set".postln;
    };
}, "/testament/filter");

// One OSCdef for every voice index, via the OSC address pattern. The
// index is the last path segment; a non-numeric tail or an index at or
// above maxVoices is a typed warning, never a voice-0 mis-trigger.
OSCdef(\testament_voice, { |msg|
    var tail, index, freq, amp, wave, detune, pan;
    tail = msg[0].asString.split($/).last;
    if(tail.size == 0 or: { tail.every({ |c| c.isDecDigit }).not }) {
        "TESTAMENT: bad_args: /testament/voice/N needs a numeric index, got '%'".format(tail).postln;
    } {
        index = tail.asInteger;
        if(index >= ~testament[\maxVoices]) {
            "TESTAMENT: voice index % out of range (max %)".format(index, ~testament[\maxVoices]).postln;
        } {
            if(msg.size < 6) {
                "TESTAMENT: bad_args: /testament/voice/% needs <freq> <amp> <waveform> <detune> <pan>".format(index).postln;
            } {
                freq = msg[1].asFloat;
                amp = msg[2].asFloat;
                wave = msg[3];
                detune = msg[4].asFloat;
                pan = msg[5].asFloat;
                ~testamentVoiceTrigger.(index, freq, amp, wave, detune, pan);
            };
        };
    };
}, "/testament/voice/*");

"--- BRAHMA: Engine Voice Manager Online ---".postln;
)
