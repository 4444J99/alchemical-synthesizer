(
// Testament sonic bridge receiver (alchemical-synthesizer#127).
//
// Boots a throwaway server, loads 16_engine_responders.scd, then sends the
// engine's actual OSC messages (organvm-engine osc_bridge.py
// build_osc_messages, OE main 1e4bec99) at the language port and asserts
// the receiver stores them and sounds the voices. Run with:
//   python3 tools/test-supercollider.py brahma/sc/tests/testament_receiver.scd
// Needs SuperCollider (sclang); not run by CI.
var server, options, check, root, sender;
check = { |condition, label|
    if(condition.not) { Error("FAIL: " ++ label).throw };
    ("PASS: " ++ label).postln;
};
root = thisProcess.nowExecutingPath.dirname.dirname;
options = ServerOptions.new.numInputBusChannels_(0).numOutputBusChannels_(2).memSize_(8192).maxNodes_(128);
server = Server(\brahmaTestamentTest, NetAddr("127.0.0.1", NetAddr.langPort + 1), options);
if("BRAHMA_SCSYNTH".getenv.notNil) { Server.program = "BRAHMA_SCSYNTH".getenv };
server.waitForBoot({
    Routine({
        var oldVoice0;
        try {
            // The SynthDef .add must reach this server, so it becomes the
            // default before the responders file loads.
            Server.default = server;
            (root +/+ "16_engine_responders.scd").load;
            check.value(OSCdef(\testament_master).notNil, "testament master OSCdef registered");
            check.value(OSCdef(\testament_bpm).notNil, "testament bpm OSCdef registered");
            check.value(OSCdef(\testament_env).notNil, "testament env OSCdef registered");
            check.value(OSCdef(\testament_filter).notNil, "testament filter OSCdef registered");
            check.value(OSCdef(\testament_voice).notNil, "testament voice OSCdef registered");
            check.value(SynthDescLib.global.at(\testament_voice).notNil, "testament voice SynthDef registered");
            server.sync;

            sender = NetAddr("127.0.0.1", NetAddr.langPort);
            // One full portrait, as the engine sends it: master, env,
            // filter, then one voice per organ index.
            sender.sendMsg("/testament/master", 0.5);
            sender.sendMsg("/testament/env", 0.01, 0.2, 0.8, 0.5);
            sender.sendMsg("/testament/filter", 4000.0, 0.2);
            sender.sendMsg("/testament/bpm", 132.5);
            sender.sendMsg("/testament/voice/0", 440.0, 0.3, "saw", 5.0, 0.0);
            sender.sendMsg("/testament/voice/1", 330.0, 0.2, "sine", 0.0, -0.5);
            0.7.wait;
            check.value(~testament[\master] == 0.5, "master stored");
            check.value(~testament[\attack] == 0.01 and: { ~testament[\sustain] == 0.8 }, "env stored");
            check.value(~testament[\cutoff] == 4000.0, "filter cutoff stored");
            check.value(~testament[\bpm] == 132.5, "bpm stored (no Chronos clock in this process)");
            check.value(~testament[\voices][0].notNil, "voice 0 sounding");
            check.value(~testament[\voices][1].notNil, "voice 1 sounding");

            // Retriggering a voice index replaces its node, never duplicates it.
            oldVoice0 = ~testament[\voices][0];
            sender.sendMsg("/testament/voice/0", 220.0, 0.3, "tri", 0.0, 0.5);
            0.5.wait;
            check.value(~testament[\voices][0].notNil and: { ~testament[\voices][0] !== oldVoice0 },
                "retrigger replaces voice 0 node");

            // Unknown waveform falls back to sine and still sounds.
            sender.sendMsg("/testament/voice/2", 550.0, 0.2, "fuzz", 0.0, 0.0);
            0.5.wait;
            check.value(~testament[\voices][2].notNil, "unknown waveform falls back to sine, voice sounds");

            // Out-of-range index is ignored, never a voice-0 mis-trigger.
            sender.sendMsg("/testament/voice/99", 440.0, 0.3, "saw", 0.0, 0.0);
            0.5.wait;
            check.value(~testament[\voices][99].isNil, "voice index 99 ignored");

            // Short env message is a typed warning, not a state change.
            sender.sendMsg("/testament/env", 0.9);
            0.4.wait;
            check.value(~testament[\attack] == 0.01, "short env message leaves state unchanged");

            // Master retunes live voices; free-all empties the voice table.
            sender.sendMsg("/testament/master", 0.9);
            0.4.wait;
            check.value(~testament[\master] == 0.9, "master retuned live");
            ~testamentFreeAll.();
            check.value(~testament[\voices].size == 0, "free-all empties the voice table");

            "BRAHMA_TEST_PASS".postln; 0.exit;
        } { |err| err.reportError; 1.exit; };
    }).play;
});
)
