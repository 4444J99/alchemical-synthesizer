/*
  Brahma Meta-Rack: Infrastructure & Backplane
  Phase 1: Environment Setup (Expanded for Mega Feature Suite)
*/

(
// 1. Server Boot & Configuration
s = Server.local;
s.options.numAudioBusChannels = 2048;
s.options.numControlBusChannels = 8192;
s.options.memSize = 8192 * 32; // Expanded for wavetable, FFT, convolution, granular
s.options.numBuffers = 4096;   // Expanded for wavetable banks, samples, IRs
s.options.maxNodes = 4096;     // Expanded for large patch bay + many voices
s.waitForBoot({

    "--- BRAHMA: Server Booted ---".postln;

    // 2. Group Hierarchy (~SC_GRP)
    // Order: Input -> Binding -> Analysis -> Transmutation -> Protection -> Release
    ~SC_GRP = (
        root: Group.head(s),
        ia: nil, bc: nil, ae: nil, te: nil, pr: nil, rr: nil,

        // Organism sub-groups: per-organism isolation within the main chain
        organisms: Dictionary.new,

        // Helper: create organism-specific sub-groups within the main chain
        createOrganismGroups: { |self, name|
            var grps = (
                ia: Group.tail(self[\ia]),
                bc: Group.tail(self[\bc]),
                ae: Group.tail(self[\ae]),
                te: Group.tail(self[\te]),
                pr: Group.tail(self[\pr]),
                rr: Group.tail(self[\rr])
            );
            self[\organisms].put(name.asSymbol, grps);
            "SC_GRP: Organism sub-groups created for '%'".format(name).postln;
            grps;
        },

        // Helper: free organism sub-groups
        freeOrganismGroups: { |self, name|
            var grps = self[\organisms][name.asSymbol];
            if(grps.notNil) {
                grps.keysValuesDo({ |k, g| g.free });
                self[\organisms].removeAt(name.asSymbol);
                "SC_GRP: Organism sub-groups freed for '%'".format(name).postln;
            };
        }
    );

    // Build main groups in strict signal-flow order
    ~SC_GRP[\ia] = Group.after(~SC_GRP[\root]);
    ~SC_GRP[\bc] = Group.after(~SC_GRP[\ia]);
    ~SC_GRP[\ae] = Group.after(~SC_GRP[\bc]);
    ~SC_GRP[\te] = Group.after(~SC_GRP[\ae]);
    ~SC_GRP[\pr] = Group.after(~SC_GRP[\te]);
    ~SC_GRP[\rr] = Group.after(~SC_GRP[\pr]);

    // 3. Bus Dictionary (~SC_BUS)
    ~SC_BUS = Dictionary.new;

    // Global Audio Buses (Virtual Rack Backplane)
    ~SC_BUS.add(\bus_audio_shared -> Bus.audio(s, 1));
    ~SC_BUS.add(\master_bus -> Bus.audio(s, 2));      // Stereo master
    ~SC_BUS.add(\cue_bus -> Bus.audio(s, 2));          // Headphone cue

    // Aux send/return buses (8 sends)
    8.do({ |i|
        ~SC_BUS.add(("aux_send_" ++ i).asSymbol -> Bus.audio(s, 2));
    });

    // 4. Global Registry (~BRAHMA_REGISTRY)
    ~BRAHMA_REGISTRY = (
        entities: Dictionary.new,
        trait_maps: Dictionary.new,
        lineage_graph: Dictionary.new,
        nextEntityId: 3000, // Auto-increment for new entities

        registerEntity: { |self, id, type, traits|
            "Registering Entity: % (%)".format(id, type).postln;
            self.entities.put(id, (type: type, traits: traits, created: Date.getDate));
        },

        getTraits: { |self, id|
            self.entities[id] !? { |e| e[\traits] };
        },

        // Auto-assign next entity ID
        nextId: { |self|
            var id = self[\nextEntityId];
            self[\nextEntityId] = id + 1;
            id;
        }
    );

    // 5. Global Tuning State (~BRAHMA_TUNING)
    ~BRAHMA_TUNING = (
        currentScale: nil,  // BrahmaScale instance (set by 02_microtonality)
        rootHz: 440.0,
        transpose: 0        // Semitone offset
    );

    // 6. The Bridge State (~BRIDGE)
    ~BRIDGE = (
        domains: Dictionary.new,
        active_links: List.new,

        lines: (
            cv: 0.0,
            clk: 0,
            flag: 0,
            data: nil,
            audio: nil
        ),

        master_id: nil,
        master_lease_expiry: 0
    );

    // Initialize Domains (4 default zones)
    4.do { |i| ~BRIDGE.domains.put(i, (id: i, modules: List.new)) };

    "--- BRAHMA: Infrastructure Ready ---".postln;
    "Groups: %, %, %, %, %, %".format(~SC_GRP[\ia], ~SC_GRP[\bc], ~SC_GRP[\ae], ~SC_GRP[\te], ~SC_GRP[\pr], ~SC_GRP[\rr]).postln;
    "Audio buses: %, Control buses: %".format(s.options.numAudioBusChannels, s.options.numControlBusChannels).postln;
});
)
