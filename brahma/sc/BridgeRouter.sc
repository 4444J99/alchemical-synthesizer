/*
  BRIDGE__DOMAIN_ROUTER__v1
  Inter-Domain Routing Protocol
*/

BridgeRouter {
    classvar <tickHz = 1000;
    
    *emitLinkSet { |bridgeState, src, dst, mode, ttl|
        // bridgeState is the ~BRIDGE dictionary
        var link = (
            src: src, 
            dst: dst, 
            mode: mode, 
            ttl: ttl, 
            expiry: Date.getDate.rawSeconds + (ttl/1000.0)
        );
        
        bridgeState.active_links.add(link);
        "BRIDGE: Link Set % -> % (Mode: %, TTL: %)".format(src, dst, mode, ttl).postln;
    }
    
    *tick { |bridgeState|
        var now = Date.getDate.rawSeconds;
        
        // Remove expired links
        bridgeState.active_links = bridgeState.active_links.select { |link|
            link.expiry > now
        };
        
        // Arbitration logic would go here
    }
}
