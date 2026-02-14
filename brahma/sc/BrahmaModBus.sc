/*
  BrahmaModBus: Universal Modulation Bus Allocator
  Manages a pool of control buses for CV routing between any
  source and destination in the Brahma system.
*/

BrahmaModBus {
    var <server;
    var <poolSize;
    var <busPool;         // Array of Bus objects
    var <busInUse;        // Array of booleans
    var <routes;          // Dictionary: routeId -> (srcId, dstId, bus, amount, offset, scale, curve, synthNode)
    var <sources;         // Dictionary: name -> (bus, type[\audio, \control], description)
    var <destinations;    // Dictionary: name -> (bus, paramName, synthNode, description)
    var <nextRouteId;

    *new { |server, poolSize=256|
        ^super.new.init(server, poolSize);
    }

    init { |srv, ps|
        server = srv;
        poolSize = ps;
        busPool = Array.fill(poolSize, { Bus.control(server, 1) });
        busInUse = Array.fill(poolSize, false);
        routes = Dictionary.new;
        sources = Dictionary.new;
        destinations = Dictionary.new;
        nextRouteId = 0;
    }

    // ==========================================
    // SOURCE / DESTINATION REGISTRY
    // ==========================================

    registerSource { |name, bus, type=\control, description=""|
        sources.put(name.asSymbol, (
            bus: bus,
            type: type,
            description: description
        ));
    }

    unregisterSource { |name|
        // Disconnect all routes from this source
        routes.keysValuesDo({ |id, route|
            if(route[\srcId] == name.asSymbol) {
                this.disconnect(id);
            };
        });
        sources.removeAt(name.asSymbol);
    }

    registerDestination { |name, paramName, description=""|
        destinations.put(name.asSymbol, (
            paramName: paramName,
            description: description
        ));
    }

    unregisterDestination { |name|
        routes.keysValuesDo({ |id, route|
            if(route[\dstId] == name.asSymbol) {
                this.disconnect(id);
            };
        });
        destinations.removeAt(name.asSymbol);
    }

    // ==========================================
    // BUS ALLOCATION
    // ==========================================

    allocBus {
        poolSize.do({ |i|
            if(busInUse[i].not) {
                busInUse[i] = true;
                ^busPool[i];
            };
        });
        "BrahmaModBus: Pool exhausted! No free buses.".warn;
        ^nil;
    }

    freeBus { |bus|
        poolSize.do({ |i|
            if(busPool[i] === bus) {
                busInUse[i] = false;
                ^true;
            };
        });
        ^false;
    }

    numFree {
        ^busInUse.count({ |b| b.not });
    }

    numUsed {
        ^busInUse.count({ |b| b });
    }

    // ==========================================
    // ROUTING (Connect / Disconnect)
    // ==========================================

    // Connect source to destination with attenuverter params
    connect { |srcName, dstName, amount=1.0, offset=0.0, scale=1.0, curve=0|
        var src = sources[srcName.asSymbol];
        var dst = destinations[dstName.asSymbol];
        var bus, routeId;

        if(src.isNil) {
            ("BrahmaModBus: Source not found: " ++ srcName).warn;
            ^nil;
        };
        if(dst.isNil) {
            ("BrahmaModBus: Destination not found: " ++ dstName).warn;
            ^nil;
        };

        bus = this.allocBus;
        if(bus.isNil) { ^nil };

        routeId = nextRouteId;
        nextRouteId = nextRouteId + 1;

        routes.put(routeId, (
            srcId: srcName.asSymbol,
            dstId: dstName.asSymbol,
            srcBus: src[\bus],
            bus: bus,
            amount: amount,
            offset: offset,
            scale: scale,
            curve: curve,
            synthNode: nil
        ));

        "BrahmaModBus: Route % connected (% -> %)".format(routeId, srcName, dstName).postln;
        ^routeId;
    }

    disconnect { |routeId|
        var route = routes[routeId];
        if(route.notNil) {
            if(route[\synthNode].notNil) {
                route[\synthNode].free;
            };
            this.freeBus(route[\bus]);
            routes.removeAt(routeId);
            "BrahmaModBus: Route % disconnected".format(routeId).postln;
            ^true;
        };
        ^false;
    }

    // Update route attenuverter parameters
    setRouteParams { |routeId, amount, offset, scale, curve|
        var route = routes[routeId];
        if(route.notNil) {
            if(amount.notNil) { route[\amount] = amount };
            if(offset.notNil) { route[\offset] = offset };
            if(scale.notNil) { route[\scale] = scale };
            if(curve.notNil) { route[\curve] = curve };
            if(route[\synthNode].notNil) {
                route[\synthNode].set(
                    \amount, route[\amount],
                    \offset, route[\offset],
                    \scale, route[\scale]
                );
            };
        };
    }

    // Get all active routes
    activeRoutes {
        ^routes.copy;
    }

    // Get routes for a specific source
    routesFromSource { |srcName|
        ^routes.select({ |r| r[\srcId] == srcName.asSymbol });
    }

    // Get routes to a specific destination
    routesToDest { |dstName|
        ^routes.select({ |r| r[\dstId] == dstName.asSymbol });
    }

    // ==========================================
    // CLEANUP
    // ==========================================

    freeAll {
        routes.keysValuesDo({ |id, route|
            if(route[\synthNode].notNil) { route[\synthNode].free };
        });
        routes.clear;
        busInUse = Array.fill(poolSize, false);
        "BrahmaModBus: All routes freed, pool reset".postln;
    }

    free {
        this.freeAll;
        busPool.do({ |b| b.free });
        "BrahmaModBus: Fully freed".postln;
    }
}
