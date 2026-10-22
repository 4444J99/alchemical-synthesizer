/*
  Tier 1: LIVE GATEWAY — engine-side responders for the browser/agent workbench.

  Adds, without touching the IMMUNE governor or any existing responder:

    /brahma/live/play  <engine> <instance> <note> <vel> <dur> [param val ...]
        Trigger through the existing voice manager (16_engine_responders.scd) and
        auto-release after <dur> seconds, so pattern events never leave hanging notes.
    /brahma/live/set   <instance> <param> <val>
    /brahma/live/panic                       stop-all (never s.freeAll: that would kill IMMUNE)
    /brahma/live/ping                        health probe

  Replies go to the web gateway on 127.0.0.1:57122 (same channel as the other broadcasts):
    /brahma/live/error <code> <message>      typed failure (unknown_engine, bad_args, ...)
    /brahma/live/pong  <module_count> <live_voice_count>
    /brahma/live/panic/done <voices_freed> <instances_freed>

  Load after 16_engine_responders.scd.
*/

(
~live_gateway = (
    web: NetAddr("127.0.0.1", 57122),
    tasks: IdentitySet.new,
    maxVoiceSecs: 30
);

~live_error = { |code, msg|
    ~live_gateway[\web].sendMsg("/brahma/live/error", code.asString, msg.asString);
    ("LIVE: % — %".format(code, msg)).postln;
};

// Call an existing OSCdef's function directly, so behaviour stays identical to
// the OSC path (no duplicated voice-allocation logic).
~live_call = { |name, msg|
    var def = OSCdef(name);
    if(def.notNil and: { def.func.notNil }) {
        def.func.value(msg, nil, nil, nil);
        true
    } {
        false
    };
};

~live_voice_count = {
    var n = 0;
    ~engine_voices.do({ |inst| n = n + inst[\voices].size });
    n
};

OSCdef(\live_play, { |msg|
    var engine, instance, note, vel, dur, extra, spec, task, ok;
    if(msg.size < 6) {
        ~live_error.("bad_args", "play needs <engine> <instance> <note> <vel> <dur>");
    } {
        engine = msg[1].asSymbol;
        instance = msg[2].asSymbol;
        note = msg[3].asInteger;
        vel = msg[4].asFloat;
        dur = msg[5].asFloat;
        extra = msg.copyToEnd(6);
        spec = ~module_registry.getSpec(engine);
        case
        { spec.isNil } { ~live_error.("unknown_engine", "no such engine: %".format(engine)) }
        { note < 0 or: { note > 127 } } { ~live_error.("bad_args", "note out of range 0..127: %".format(note)) }
        { vel < 0 or: { vel > 1 } } { ~live_error.("bad_args", "velocity out of range 0..1: %".format(vel)) }
        { dur <= 0 or: { dur > ~live_gateway[\maxVoiceSecs] } } {
            ~live_error.("bad_args", "duration out of range 0..%: %".format(~live_gateway[\maxVoiceSecs], dur))
        }
        { extra.size.odd } { ~live_error.("bad_args", "params must be name/value pairs") }
        {
            ok = ~live_call.(\engine_noteOn, ["/brahma/engine/noteOn", engine, instance, note, vel] ++ extra);
            if(ok.not) {
                ~live_error.("engine_unavailable", "engine voice manager not loaded");
            } {
                task = Routine({
                    dur.wait;
                    ~live_call.(\engine_noteOff, ["/brahma/engine/noteOff", instance, note]);
                    ~live_gateway[\tasks].remove(thisThread);
                });
                ~live_gateway[\tasks].add(task);
                task.play(SystemClock);
            };
        };
    };
}, "/brahma/live/play");

OSCdef(\live_set, { |msg|
    var instance, param, val;
    if(msg.size < 4) {
        ~live_error.("bad_args", "set needs <instance> <param> <val>");
    } {
        instance = msg[1].asSymbol;
        param = msg[2].asSymbol;
        val = msg[3].asFloat;
        if(~engine_voices[instance].isNil) {
            ~live_error.("unknown_instance", "no such instance: %".format(instance));
        } {
            ~live_call.(\engine_set, ["/brahma/engine/set", instance, param, val]);
        };
    };
}, "/brahma/live/set");

OSCdef(\live_panic, {
    var voices = 0, insts = 0;
    // 1. cancel every pending auto-release so nothing fires after the panic
    ~live_gateway[\tasks].do({ |t| t.stop });
    ~live_gateway[\tasks] = IdentitySet.new;
    // 2. transports and generators (existing responders, looked up by path)
    ["/chronos/transport/stop", "/golem/transport/stop", "/brahma/demo/stop", "/brahma/midi/panic"].do({ |path|
        OSCdef.all.values.select({ |d| d.path == path.asSymbol }).do({ |d|
            try { d.func.value([path], nil, nil, nil) };
        });
    });
    // 3. every engine voice
    ~engine_voices.do({ |inst|
        inst[\voices].do({ |s| s.free; voices = voices + 1 });
        inst[\voices] = IdentityDictionary.new;
    });
    // 4. every instantiated registry module
    ~module_registry[\modules].do({ |spec|
        spec[\instances].keys.asArray.do({ |name|
            ~module_registry.freeInstance(spec[\name], name);
            insts = insts + 1;
        });
    });
    ~live_gateway[\web].sendMsg("/brahma/live/panic/done", voices, insts);
    "LIVE: panic — % voices, % instances freed".format(voices, insts).postln;
}, "/brahma/live/panic");

OSCdef(\live_ping, {
    ~live_gateway[\web].sendMsg("/brahma/live/pong", ~module_registry.count, ~live_voice_count.value);
}, "/brahma/live/ping");

"--- BRAHMA: Live Gateway Responders Online ---".postln;
)
