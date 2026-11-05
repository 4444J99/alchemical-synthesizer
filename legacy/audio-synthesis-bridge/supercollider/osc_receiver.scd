/*
 * Omni-Performative Engine — SuperCollider OSC Receiver
 *
 * Receives consensus state from the Node.js server and routes
 * parameters to synthesis engines.
 *
 * Usage:
 *   1. Boot the server: s.boot;
 *   2. Load synth definitions: "synth_defs.scd".loadRelative;
 *   3. Execute this file: thisProcess.nowExecutingPath.dirname +/+ "osc_receiver.scd".load;
 *
 * OSC Address Schema:
 *   /ope/intensity     float (0-1)
 *   /ope/density       float (0-1)
 *   /ope/pitch         float (0-1)
 *   /ope/state         float[5]  [intensity, density, pitch, participants, variance]
 *   /ope/participants  int
 *   /ope/mute          int (0/1)
 *   /ope/heartbeat     int (timestamp)
 */

(
// ============================================================================
// Configuration
// ============================================================================

~opePort = 57120;  // Must match server OSC_PORT
~debug = true;     // Print incoming messages

// ============================================================================
// State Variables
// ============================================================================

~state = (
    intensity: 0.5,
    density: 0.5,
    pitch: 0.5,
    participants: 0,
    variance: 0.0,
    muted: false,
    lastHeartbeat: 0
);

// ============================================================================
// Synth References (populated when synths are created)
// ============================================================================

~synths = ();

// ============================================================================
// Parameter Mapping Functions
// ============================================================================

// Map intensity (0-1) to amplitude and filter cutoff
~mapIntensity = { |val|
    var amp = val.linexp(0, 1, 0.01, 0.8);
    var cutoff = val.linexp(0, 1, 200, 8000);
    [amp, cutoff]
};

// Map density (0-1) to grain rate and harmonic complexity
~mapDensity = { |val|
    var rate = val.linexp(0, 1, 0.5, 20);
    var harmonics = val.linlin(0, 1, 1, 8).round;
    [rate, harmonics]
};

// Map pitch (0-1) to base frequency
~mapPitch = { |val|
    var freq = val.linexp(0, 1, 55, 880);  // A1 to A5
    freq
};

// ============================================================================
// Update Synth Parameters
// ============================================================================

~updateSynths = {
    var intensity = ~mapIntensity.(~state.intensity);
    var density = ~mapDensity.(~state.density);
    var pitch = ~mapPitch.(~state.pitch);
    
    // Update main drone synth
    if(~synths[\drone].notNil) {
        ~synths[\drone].set(
            \amp, intensity[0],
            \cutoff, intensity[1],
            \freq, pitch
        );
    };
    
    // Update granular layer
    if(~synths[\granular].notNil) {
        ~synths[\granular].set(
            \rate, density[0],
            \amp, intensity[0] * 0.5
        );
    };
    
    // Update rhythmic element
    if(~synths[\rhythm].notNil) {
        ~synths[\rhythm].set(
            \density, density[0],
            \freq, pitch,
            \amp, intensity[0] * 0.3
        );
    };
    
    if(~debug) {
        "Updated synths: intensity=%, density=%, pitch=%".format(
            ~state.intensity.round(0.01),
            ~state.density.round(0.01),
            ~state.pitch.round(0.01)
        ).postln;
    };
};

// ============================================================================
// OSC Responders
// ============================================================================

// Individual parameter updates
OSCdef(\opeIntensity, { |msg|
    ~state.intensity = msg[1];
    ~updateSynths.();
}, '/ope/intensity');

OSCdef(\opeDensity, { |msg|
    ~state.density = msg[1];
    ~updateSynths.();
}, '/ope/density');

OSCdef(\opePitch, { |msg|
    ~state.pitch = msg[1];
    ~updateSynths.();
}, '/ope/pitch');

// Bundled state update (more efficient)
OSCdef(\opeState, { |msg|
    ~state.intensity = msg[1];
    ~state.density = msg[2];
    ~state.pitch = msg[3];
    ~state.participants = msg[4];
    ~state.variance = msg[5];
    ~updateSynths.();
}, '/ope/state');

// Participant count
OSCdef(\opeParticipants, { |msg|
    ~state.participants = msg[1];
    if(~debug) {
        "Participants: %".format(~state.participants).postln;
    };
}, '/ope/participants');

// Mute control
OSCdef(\opeMute, { |msg|
    ~state.muted = msg[1] == 1;
    
    if(~state.muted) {
        // Fade out all synths
        ~synths.do { |synth| synth.set(\gate, 0) };
        "*** MUTED ***".postln;
    } {
        // Restore synths
        ~synths.do { |synth| synth.set(\gate, 1) };
        "*** UNMUTED ***".postln;
    };
}, '/ope/mute');

// Heartbeat (connection monitoring)
OSCdef(\opeHeartbeat, { |msg|
    ~state.lastHeartbeat = msg[1];
}, '/ope/heartbeat');

// ============================================================================
// Initialization
// ============================================================================

"╔══════════════════════════════════════════════════════════════╗".postln;
"║     OMNI-PERFORMATIVE ENGINE — SuperCollider Receiver        ║".postln;
"╠══════════════════════════════════════════════════════════════╣".postln;
"║  Listening on port: %                                    ║".format(~opePort).postln;
"║  Debug mode: %                                             ║".format(if(~debug, "ON ", "OFF")).postln;
"╠══════════════════════════════════════════════════════════════╣".postln;
"║  Load synth definitions:                                     ║".postln;
"║    \"synth_defs.scd\".loadRelative;                           ║".postln;
"║                                                              ║".postln;
"║  Start synthesis:                                            ║".postln;
"║    ~startPerformance.();                                     ║".postln;
"║                                                              ║".postln;
"║  Stop synthesis:                                             ║".postln;
"║    ~stopPerformance.();                                      ║".postln;
"╚══════════════════════════════════════════════════════════════╝".postln;

// ============================================================================
// Performance Control Functions
// ============================================================================

~startPerformance = {
    // Load synth defs if not already loaded
    if(SynthDescLib.global[\opeDrone].isNil) {
        "Loading synth definitions...".postln;
        (thisProcess.nowExecutingPath.dirname +/+ "synth_defs.scd").load;
        s.sync;
    };
    
    // Create synths
    ~synths[\drone] = Synth(\opeDrone);
    ~synths[\granular] = Synth(\opeGranular);
    ~synths[\rhythm] = Synth(\opeRhythm);
    
    "Performance started.".postln;
};

~stopPerformance = {
    ~synths.do { |synth| synth.free };
    ~synths = ();
    "Performance stopped.".postln;
};

// Cleanup on Cmd+Period
CmdPeriod.add({
    OSCdef(\opeIntensity).free;
    OSCdef(\opeDensity).free;
    OSCdef(\opePitch).free;
    OSCdef(\opeState).free;
    OSCdef(\opeParticipants).free;
    OSCdef(\opeMute).free;
    OSCdef(\opeHeartbeat).free;
    "OPE OSC responders freed.".postln;
});

)
