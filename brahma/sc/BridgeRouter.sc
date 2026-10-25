/*
  BRIDGE__DOMAIN_ROUTER__v2
  Inter-Domain Routing Protocol — distributed backplane extension
  
  v1: single-host link sets with TTL expiry.
  v2: adds multi-host peer discovery, link redundancy, clock-sync offset
      tracking, and heartbeat health monitoring for the distributed OSC backplane.
*/

BridgeRouter {
    classvar <tickHz = 1000;
    classvar <peers = Dictionary.new;      // host -> {port, lastSeen, offsetMs}
    classvar <linkPaths = Dictionary.new;  // "src->dst" -> List of {pathId, mode, ttl, expiry, healthy}
    classvar <heartbeatInterval = 5000;    // ms between peer heartbeats
    classvar <lastHeartbeat = 0;
    
    // --- v1: emitLinkSet (backward compatible) ---
    *emitLinkSet { |bridgeState, src, dst, mode, ttl|
        var link = (
            src: src, 
            dst: dst, 
            mode: mode, 
            ttl: ttl, 
            expiry: Date.getDate.rawSeconds + (ttl/1000.0),
            pathId: 0,
            healthy: true
        );
        
        // Register as a link path for redundancy tracking
        var key = src ++ "->" ++ dst;
        var paths = ~linkPaths.at(key);
        if (paths.isNil) {
            paths = List.new;
            ~linkPaths[key] = paths;
        };
        paths.add(link.copy);
        
        bridgeState.active_links.add(link);
        "BRIDGE: Link Set % -> % (Mode: %, TTL: %, path #%)".format(src, dst, mode, ttl, paths.size).postln;
    }
    
    // --- v2: register a peer host for distributed OSC ---
    *registerPeer { |host, port, offsetMs|
        offsetMs = if (offsetMs.notNil) { offsetMs } { 0 };
        ~peers[host] = Dictionary.newFromPairs([
            #[\port -> port,
              \lastSeen -> Date.getDate.rawSeconds * 1000,
              \offsetMs -> offsetMs,
              \healthy -> true]
        ]);
        "BRIDGE: Peer registered %:% (clock offset % ms)".format(host, port, offsetMs).postln;
    }
    
    // --- v2: record a heartbeat from a peer ---
    *peerHeartbeat { |host, timestampMs|
        var peer = ~peers.at(host);
        if (peer.notNil) {
            peer[\lastSeen] = timestampMs;
            peer[\healthy] = true;
            // Estimate clock offset from round-trip (simplified: one-way assumption)
            var now = Date.getDate.rawSeconds * 1000;
            var offset = now - timestampMs;
            peer[\offsetMs] = offset.clip(-1000, 1000);
        } {
            ("BRIDGE: Heartbeat from unknown peer %".format(host)).warn;
        };
    }
    
    // --- v2: mark a link path unhealthy (for redundancy failover) ---
    *markLinkUnhealthy { |src, dst, pathId|
        var key = src ++ "->" ++ dst;
        var paths = ~linkPaths.at(key);
        if (paths.notNil) {
            paths.do { |p|
                if (p[\pathId] == pathId) { p[\healthy] = false; };
            };
            ("BRIDGE: Link path % -> % #% marked unhealthy".format(src, dst, pathId)).warn;
        };
    }
    
    // --- v2: get healthy link paths for a src->dst pair (redundancy) ---
    *healthyPaths { |src, dst|
        var key = src ++ "->" ++ dst;
        var paths = ~linkPaths.at(key);
        if (paths.isNil) { ^List.new; };
        ^paths.select { |p| p[\healthy] };
    }
    
    // --- v2: tick — expiry + peer health + clock drift ---
    *tick { |bridgeState|
        var now = Date.getDate.rawSeconds;
        var nowMs = now * 1000;
        
        // Remove expired v1 links
        bridgeState.active_links = bridgeState.active_links.select { |link|
            link.expiry > now
        };
        
        // Expire stale link paths (TTL)
        ~linkPaths.do { |key, paths|
            ~linkPaths[key] = paths.select { |p|
                p.expiry > now
            };
        };
        
        // Peer health: mark stale peers unhealthy
        ~peers.do { |host, peer|
            var ageMs = nowMs - peer[\lastSeen];
            if (ageMs > 30000) {  // 30 s stale = unhealthy
                peer[\healthy] = false;
                ("BRIDGE: Peer % stale (%d ms) — marking unhealthy".format(host, ageMs)).warn;
            };
        };
        
        // Heartbeat: emit to all peers if interval elapsed
        if (nowMs - ~lastHeartbeat > ~heartbeatInterval) {
            ~lastHeartbeat = nowMs;
            "BRIDGE: Heartbeat cycle (%d peers, %d link keys)".format(~peers.size, ~linkPaths.size).postln;
        };
        
        // Arbitration logic would go here
    }
    
    // --- v2: peer status summary ---
    *peerStatus {
        ^~peers.collect { |host, peer|
            Dictionary.newFromPairs([
                #[\host -> host,
                  \port -> peer[\port],
                  \healthy -> peer[\healthy],
                  \offsetMs -> peer[\offsetMs],
                  \lastSeenAgoMs -> (Date.getDate.rawSeconds * 1000 - peer[\lastSeen])]
            ]);
        }.asArray;
    }
    
    // --- v1 (unchanged) ---
    *checkPermission { |srcId, dstId, mode|
        ^true;
    }
    
    *issueCapabilityToken { |entityId, capability|
        ^Hash.new((entityId ++ capability ++ Date.getDate).asString);
    }
}