/*
  Tier 0: SPINE — Module Discovery Registry
  Central registry for all Brahma modules: engines, FX, modular, daemons, organisms.
  Provides discovery, instantiation, parameter control, and OSC query interface.
  Broadcasts module metadata to port 57122 for web UI consumption.
*/

(
~module_registry = (
    modules: IdentityDictionary.new,

    // Register a module with full parameter specs
    register: { |self, name, category, synthDef, params, group, description|
        self[\modules].put(name.asSymbol, (
            name: name.asSymbol,
            category: category.asSymbol,
            synthDef: synthDef.asSymbol,
            params: params,
            group: group ? ~sc_grp[\te],
            description: description ? "",
            instances: IdentityDictionary.new
        ));
    },

    // Instantiate a module as a named Synth
    instantiate: { |self, moduleName, instanceName, args, outBus, group|
        var spec = self[\modules][moduleName.asSymbol];
        if(spec.notNil) {
            var synthArgs = [\outBus, outBus ? 0];
            var synth;
            // Apply default param values, then override with args
            spec[\params].do({ |p|
                synthArgs = synthArgs ++ [p[\name].asSymbol, p[\default]];
            });
            if(args.notNil) {
                args.pairsDo({ |k, v|
                    var idx = synthArgs.indexOf(k.asSymbol);
                    if(idx.notNil) { synthArgs[idx + 1] = v };
                });
            };
            synth = Synth(spec[\synthDef], synthArgs,
                group ? spec[\group], \addToTail);
            spec[\instances].put(instanceName.asSymbol, (
                synth: synth,
                params: synthArgs,
                outBus: outBus ? 0
            ));
            "MODULE_REGISTRY: Instantiated '%' as '%' (node %)".format(
                moduleName, instanceName, synth.nodeID).postln;
            synth;
        } {
            "MODULE_REGISTRY: Unknown module '%'".format(moduleName).postln;
            nil;
        };
    },

    // Set a parameter on a specific instance
    setParam: { |self, moduleName, instanceName, param, value|
        var spec = self[\modules][moduleName.asSymbol];
        if(spec.notNil) {
            var inst = spec[\instances][instanceName.asSymbol];
            if(inst.notNil) {
                inst[\synth].set(param.asSymbol, value.asFloat);
            };
        };
    },

    // Free a specific instance
    freeInstance: { |self, moduleName, instanceName|
        var spec = self[\modules][moduleName.asSymbol];
        if(spec.notNil) {
            var inst = spec[\instances][instanceName.asSymbol];
            if(inst.notNil) {
                inst[\synth].free;
                spec[\instances].removeAt(instanceName.asSymbol);
                "MODULE_REGISTRY: Freed '%/%'".format(moduleName, instanceName).postln;
            };
        };
    },

    // Query: all module names sorted
    allModules: { |self|
        self[\modules].keys.asArray.sort;
    },

    // Query: modules by category
    byCategory: { |self, cat|
        self[\modules].select({ |m| m[\category] == cat.asSymbol });
    },

    // Query: get full spec for a module
    getSpec: { |self, name|
        self[\modules][name.asSymbol];
    },

    // Count registered modules
    count: { |self|
        self[\modules].size;
    }
);

// ==========================================
// PD BRIDGE: Send registry data to Pure Data on port 57121
// ==========================================
~pd_bridge = NetAddr("127.0.0.1", 57121);

// ==========================================
// OSC RESPONDERS: Module Discovery
// ==========================================

// List all registered modules → broadcasts to 57122
OSCdef(\reg_list_modules, { |msg|
    var target = ~visual_cortex.target;
    ~module_registry[\modules].keysValuesDo({ |name, spec|
        target.sendMsg(
            "/brahma/registry/module",
            name.asString,
            spec[\category].asString,
            spec[\synthDef].asString,
            spec[\params].size,
            spec[\instances].size,
            spec[\description]
        );
    });
    target.sendMsg("/brahma/registry/done", ~module_registry.count);
    "MODULE_REGISTRY: Broadcast % modules".format(~module_registry.count).postln;
}, "/brahma/modules/list");

// Get params for a specific module → broadcasts to 57122
OSCdef(\reg_list_params, { |msg|
    var moduleName = msg[1].asSymbol;
    var spec = ~module_registry.getSpec(moduleName);
    var target = ~visual_cortex.target;
    if(spec.notNil) {
        spec[\params].do({ |p|
            target.sendMsg(
                "/brahma/registry/param",
                moduleName.asString,
                p[\name].asString,
                p[\default].asFloat,
                p[\min].asFloat,
                p[\max].asFloat,
                (p[\units] ? "").asString,
                (p[\desc] ? "").asString
            );
        });
        target.sendMsg("/brahma/registry/params/done", moduleName.asString, spec[\params].size);
    };
}, "/brahma/modules/params");

// List instances for a specific module → broadcasts to 57122
OSCdef(\reg_list_instances, { |msg|
    var moduleName = msg[1].asSymbol;
    var spec = ~module_registry.getSpec(moduleName);
    var target = ~visual_cortex.target;
    if(spec.notNil) {
        spec[\instances].keysValuesDo({ |instName, inst|
            target.sendMsg(
                "/brahma/registry/instance",
                moduleName.asString,
                instName.asString,
                inst[\synth].nodeID
            );
        });
    };
}, "/brahma/modules/instances");

// Instantiate a module via OSC
OSCdef(\reg_create_instance, { |msg|
    var moduleName = msg[1].asSymbol;
    var instanceName = msg[2].asSymbol;
    var outBus = if(msg.size > 3) { msg[3].asInteger } { 0 };
    // Remaining args as key-value pairs
    var args = if(msg.size > 4) {
        var a = IdentityDictionary.new;
        var i = 4;
        while({ i < (msg.size - 1) }) {
            a.put(msg[i].asSymbol, msg[i+1].asFloat);
            i = i + 2;
        };
        a;
    } { nil };
    ~module_registry.instantiate(moduleName, instanceName, args, outBus);
}, "/brahma/module/create");

// Set param on a module instance via OSC
OSCdef(\reg_set_param, { |msg|
    var moduleName = msg[1].asSymbol;
    var instanceName = msg[2].asSymbol;
    var param = msg[3].asSymbol;
    var value = msg[4].asFloat;
    ~module_registry.setParam(moduleName, instanceName, param, value);
}, "/brahma/module/set");

// Free a module instance via OSC
OSCdef(\reg_free_instance, { |msg|
    var moduleName = msg[1].asSymbol;
    var instanceName = msg[2].asSymbol;
    ~module_registry.freeInstance(moduleName, instanceName);
}, "/brahma/module/free");

// ==========================================
// OSC RESPONDERS: PD-Specific Registry Queries
// ==========================================

// PD module list: sends each module then a done message
OSCdef(\pd_list_modules, { |msg|
    ~module_registry[\modules].keysValuesDo({ |name, spec|
        ~pd_bridge.sendMsg("/pd/registry/module",
            name.asString, spec[\category].asString,
            spec[\params].size, spec[\description]);
    });
    ~pd_bridge.sendMsg("/pd/registry/done", ~module_registry.count);
    "MODULE_REGISTRY: PD broadcast % modules".format(~module_registry.count).postln;
}, "/pd/modules/list");

// PD param list: sends slot index, name, default, min, max for each param
OSCdef(\pd_list_params, { |msg|
    var moduleName = msg[1].asSymbol;
    var spec = ~module_registry.getSpec(moduleName);
    if(spec.notNil) {
        spec[\params].do({ |p, i|
            ~pd_bridge.sendMsg("/pd/registry/param",
                moduleName.asString, i,
                p[\name].asString, p[\default].asFloat,
                p[\min].asFloat, p[\max].asFloat);
        });
        ~pd_bridge.sendMsg("/pd/registry/params/done",
            moduleName.asString, spec[\params].size);
    };
}, "/pd/modules/params");

"--- BRAHMA: Module Registry Online (PD bridge: 57121) ---".postln;
)
