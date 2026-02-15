/*
  Phase 0C: Universal Modulation & Patch Bay
  Audio-rate CV routing between any source and destination
*/

(
// ==========================================
// PATCH BAY SYNTHDEF: Reads CV, scales, writes to destination
// ==========================================
SynthDef(\patch_bay_mod, {
    |srcBus=0, dstBus=0, amount=1.0, offset=0.0, scale=1.0|

    var src, out;

    src = In.kr(srcBus, 1);

    // Attenuverter: (source * amount * scale) + offset
    out = (src * amount * scale) + offset;

    Out.kr(dstBus, out);
}).add;

// Audio-rate version for FM/AM modulation
SynthDef(\patch_bay_mod_ar, {
    |srcBus=0, dstBus=0, amount=1.0, offset=0.0, scale=1.0|

    var src, out;

    src = In.ar(srcBus, 1);

    out = (src * amount * scale) + offset;

    Out.ar(dstBus, out);
}).add;

// CV-to-audio converter (for using control-rate mod at audio rate)
SynthDef(\patch_bay_kr_to_ar, {
    |srcBus=0, dstBus=0, smooth=0.005|

    var src = In.kr(srcBus, 1);
    // K2A with smoothing to prevent zipper noise
    Out.ar(dstBus, K2A.ar(Lag.kr(src, smooth)));
}).add;

// Audio-to-CV converter (for using audio signal as modulation)
SynthDef(\patch_bay_ar_to_kr, {
    |srcBus=0, dstBus=0, smooth=0.01|

    var src = In.ar(srcBus, 1);
    Out.kr(dstBus, A2K.kr(LPF.ar(src, 1 / smooth)));
}).add;

// ==========================================
// GLOBAL PATCH BAY INSTANCE
// ==========================================
~patch_bay = BrahmaModBus.new(s, 256);

// Helper: connect with synth instantiation
~patch_bay_connect = { |srcName, dstName, amount=1.0, offset=0.0, scale=1.0|
    var routeId = ~patch_bay.connect(srcName, dstName, amount, offset, scale);
    var route;

    if(routeId.notNil) {
        route = ~patch_bay.routes[routeId];
        // Instantiate the routing synth
        route[\synthNode] = Synth(\patch_bay_mod, [
            \srcBus, route[\srcBus].index,
            \dstBus, route[\bus].index,
            \amount, amount,
            \offset, offset,
            \scale, scale
        ], target: ~sc_grp[\root]); // Run in root group (before everything)
    };

    routeId;
};

~patch_bay_disconnect = { |routeId|
    ~patch_bay.disconnect(routeId);
};

// ==========================================
// OSC RESPONDERS
// ==========================================

// /brahma/patch/connect <srcName:string> <dstName:string> <amount:float> <offset:float> <scale:float>
OSCdef(\brahma_patch_connect, { |msg|
    var src = msg[1].asString;
    var dst = msg[2].asString;
    var amount = msg[3] !? _.asFloat ?? 1.0;
    var offset = msg[4] !? _.asFloat ?? 0.0;
    var scale = msg[5] !? _.asFloat ?? 1.0;
    var routeId = ~patch_bay_connect.value(src, dst, amount, offset, scale);
    if(~visual_cortex.notNil) {
        ~visual_cortex.target.sendMsg("/brahma/patch/connected", routeId ? -1, src, dst);
    };
    if(~pd_bridge.notNil) {
        ~pd_bridge.sendMsg("/pd/patch/connected", routeId ? -1, src, dst);
    };
}, "/brahma/patch/connect");

// /brahma/patch/disconnect <routeId:int>
OSCdef(\brahma_patch_disconnect, { |msg|
    var routeId = msg[1].asInteger;
    ~patch_bay_disconnect.value(routeId);
    if(~visual_cortex.notNil) {
        ~visual_cortex.target.sendMsg("/brahma/patch/disconnected", routeId);
    };
}, "/brahma/patch/disconnect");

// /brahma/patch/attenuvert <routeId:int> <amount:float> <offset:float> <scale:float>
OSCdef(\brahma_patch_attenuvert, { |msg|
    var routeId = msg[1].asInteger;
    var amount = msg[2] !? _.asFloat;
    var offset = msg[3] !? _.asFloat;
    var scale = msg[4] !? _.asFloat;
    ~patch_bay.setRouteParams(routeId, amount, offset, scale);
}, "/brahma/patch/attenuvert");

// /brahma/patch/list — broadcast all active routes
OSCdef(\brahma_patch_list, {
    if(~visual_cortex.notNil) {
        ~patch_bay.activeRoutes.keysValuesDo({ |id, route|
            ~visual_cortex.target.sendMsg("/brahma/patch/route",
                id, route[\srcId], route[\dstId], route[\amount]);
        });
    };
}, "/brahma/patch/list");

// /brahma/patch/sources — broadcast registered sources
OSCdef(\brahma_patch_sources, {
    if(~visual_cortex.notNil) {
        ~patch_bay.sources.keysValuesDo({ |name, src|
            ~visual_cortex.target.sendMsg("/brahma/patch/source", name, src[\type]);
        });
    };
}, "/brahma/patch/sources");

// /brahma/patch/destinations — broadcast registered destinations
OSCdef(\brahma_patch_dests, {
    if(~visual_cortex.notNil) {
        ~patch_bay.destinations.keysValuesDo({ |name, dst|
            ~visual_cortex.target.sendMsg("/brahma/patch/destination", name, dst[\paramName]);
        });
    };
}, "/brahma/patch/destinations");

// /brahma/patch/disconnect/named <srcName:string> <dstName:string>
OSCdef(\brahma_patch_disconnect_named, { |msg|
    var src = msg[1].asString;
    var dst = msg[2].asString;
    ~patch_bay.activeRoutes.keysValuesDo({ |id, route|
        if(route[\srcId].asString == src and: { route[\dstId].asString == dst }) {
            ~patch_bay_disconnect.value(id);
            if(~visual_cortex.notNil) {
                ~visual_cortex.target.sendMsg("/brahma/patch/disconnected", id);
            };
            if(~pd_bridge.notNil) {
                ~pd_bridge.sendMsg("/pd/patch/disconnected", id);
            };
        };
    });
}, "/brahma/patch/disconnect/named");

// Broadcast patch bay state at 10Hz for Visual Cortex
Tdef(\patch_bay_broadcast, {
    loop {
        if(~visual_cortex.notNil) {
            ~patch_bay.activeRoutes.keysValuesDo({ |id, route|
                if(route[\srcBus].notNil) {
                    var val = route[\srcBus].getSynchronous;
                    ~visual_cortex.target.sendMsg("/brahma/mod/value",
                        id, route[\srcId], route[\dstId], val * route[\amount]);
                };
            });
        };
        0.1.wait;
    };
}).play;

"--- BRAHMA: Universal Patch Bay Online (% bus pool) ---".format(~patch_bay.numFree).postln;
)
