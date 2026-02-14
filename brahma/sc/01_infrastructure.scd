/*
  Brahma Meta-Rack: Infrastructure & Backplane
  Phase 1: Environment Setup
*/

(
// 1. Server Boot & Configuration
s = Server.local;
s.options.numAudioBusChannels = 1024;
s.options.numControlBusChannels = 4096;
s.options.memSize = 8192 * 16; // Increased memory for delay buffers/spectral processing
s.waitForBoot({

    "--- BRAHMA: Server Booted ---".postln;

    // 2. Group Hierarchy (~SC_GRP)
    // Order: Input -> Binding -> Analysis -> Transmutation -> Protection -> Release
    ~SC_GRP = (
        root: Group.head(s),
        ia: Group.after(Group.head(s)), // Input Assimilation
        bc: Group.after(Group.head(s)), // Binding Core (buffer writes)
        ae: Group.after(Group.head(s)), // Analysis Extraction
        te: Group.after(Group.head(s)), // Transmutation Engine
        pr: Group.after(Group.head(s)), // Protection/Reflection
        rr: Group.after(Group.head(s))  // Release Router
    );

    // 3. Bus Dictionary (~SC_BUS)
    // Dynamic allocation for internal routing.
    ~SC_BUS = Dictionary.new;
    
    // Global Audio Buses (Virtual Rack Backplane)
    // Allocating a block for the 'Bridge' to tap into.
    ~SC_BUS.add(\bus_audio_shared -> Bus.audio(s, 1)); 
    
    // 4. Global Registry (~BRAHMA_REGISTRY)
    // Adam Kadmon's data store for EntityIDs and TraitMaps.
    ~BRAHMA_REGISTRY = (
        entities: Dictionary.new,
        trait_maps: Dictionary.new,
        lineage_graph: Dictionary.new,
        
        // Helper to register a new entity
        registerEntity: { |self, id, type, traits|
            "Registering Entity: % (%)".format(id, type).postln;
            self.entities.put(id, (type: type, traits: traits, created: Date.getDate));
        },
        
        // Helper to retrieve traits
        getTraits: { |self, id|
            self.entities[id].tryPerform(	raits)
        }
    );

    // 5. The Bridge State (~BRIDGE)
    // Simulating the I2C-style bus state in language side.
    ~BRIDGE = (
        domains: Dictionary.new, // 0..15
        active_links: List.new,
        
        // Bus Lines (Simulation)
        lines: (
            cv: 0.0,
            clk: 0,
            flag: 0,
            data: nil, // Current packet
            audio: nil // Pointer to audio bus
        ),
        
        // Arbitration State
        master_id: nil,
        master_lease_expiry: 0
    );

    // Initialize Domains (4 default zones)
    4.do { |i| ~BRIDGE.domains.put(i, (id: i, modules: List.new)) };

    "--- BRAHMA: Infrastructure Ready ---".postln;
    "Groups: %, %, %, %, %, %".format(~SC_GRP.ia, ~SC_GRP.bc, ~SC_GRP.ae, ~SC_GRP.te, ~SC_GRP.pr, ~SC_GRP.rr).postln;
});
)
