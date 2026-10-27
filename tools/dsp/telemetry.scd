(
var root = "BRAHMA_REPO_ROOT".getenv;
var packets = List.new, failures = 0, check;
check = { |condition, label|
    if(condition == true) { ("PASS " ++ label).postln } {
        failures = failures + 1; ("FAIL " ++ label).postln;
    };
};
(root +/+ "brahma/sc/11_metrics.scd").load;
(root +/+ "brahma/sc/14_visual_cortex.scd").load;
~visual_cortex.stopStream;
Tdef(\viz_stream).quant = 0;
// Replace only the OSC transport; run the actual broadcaster and task.
~visual_cortex.target = (sendMsg: { |self ... args| packets.add(args) });
~golem = (entityId: 2001);
~golem_seq = (playing: false, tempo: 120, currentStep: 0, tracks: []);
~visual_cortex.broadcastGolem;
check.(packets.any({ |p| p[0] == "/golem/seq/state" }), "sequencer state remains available");
check.(packets.any({ |p| p[0] == "/golem/organism/update" }).not,
    "no numeric organism packet without captured audio");
check.(packets.any({ |p| p[0] == "/brahma/organism/measurement/status" and: { p[3] == "unavailable" } }),
    "missing capture is explicitly unavailable");
{
    packets.clear;
    ~visual_cortex.startStream;
    0.15.wait;
    ~visual_cortex.stopStream;
    check.(packets.any({ |p| p[0] == "/brahma/organism/update" }).not,
        "normal stream never invents organism measurements");
    packets.clear;
    ~visual_cortex.demoMode = true;
    ~visual_cortex.startStream;
    0.15.wait;
    ~visual_cortex.stopStream;
    check.(packets.any({ |p| p[0] == "/brahma/organism/update" and: { p[2].beginsWith("DEMO ") } }),
        "explicit demo labels synthetic organisms");
    if(failures == 0) { "DSP_PASS telemetry".postln; 0.exit } { 1.exit };
}.fork(SystemClock);
)
