/* Validated JSON schemas shared by measured audio and non-audio trait maps.
   Every declared range must pass; strictness is schema metadata. Measurement
   confidence uses the separate provenance_min_confidence field (default 0.85).
*/
BrahmaContracts {
    *symbolize { |value|
        var result;
        if(value.isKindOf(Dictionary)) {
            result = IdentityDictionary.new;
            value.keysValuesDo { |key, item| result[key.asSymbol] = this.symbolize(item) };
            ^result;
        };
        if(value.isArray) { ^value.collect { |item| this.symbolize(item) } };
        ^value;
    }

    *finiteNumber { |value|
        ^value.isKindOf(SimpleNumber) and: { value.isNaN.not and: { value.abs < inf } };
    }

    *schemaNumber { |value|
        var number;
        if(this.finiteNumber(value)) { ^value };
        if(value.isKindOf(String) and: {
            "^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$".matchRegexp(value)
        }) { number = value.asFloat };
        ^if(this.finiteNumber(number)) { number } { nil };
    }

    *load { |path|
        var raw, value, name, required, ranges, strictness, threshold, valid = true;
        if(path.isKindOf(String).not or: { File.exists(path).not }) { ^nil };
        raw = try { path.parseJSONFile } { |error| error.errorString.warn; nil };
        if(raw.isKindOf(Dictionary).not) { ^nil };
        name = raw["name"]; required = raw["requiredKeys"];
        ranges = raw["ranges"] ? Dictionary.new;
        strictness = this.schemaNumber(raw["strictness"] ? 0.85);
        threshold = this.schemaNumber(raw["provenance_min_confidence"] ? 0.85);
        if(name.isKindOf(String).not or: { name.isEmpty or: { name == "canonical_v1" } }) { ^nil };
        if(required.isArray.not or: { required.isEmpty } or: {
            required.every { |key| key.isKindOf(String) and: {
                "^[A-Za-z_][A-Za-z0-9_]*$".matchRegexp(key)
            } }.not
        }) { ^nil };
        if(ranges.isKindOf(Dictionary).not or: {
            [strictness, threshold].every { |n| this.finiteNumber(n) and: { n.inclusivelyBetween(0, 1) } }.not
        }) { ^nil };
        value = this.symbolize(raw);
        value[\name] = name.asSymbol;
        value[\requiredKeys] = required.collect(_.asSymbol);
        value[\strictness] = strictness;
        value[\provenance_min_confidence] = threshold;
        value[\ranges] = Dictionary.new;
        if(value[\requireMeasured] == "true") { value[\requireMeasured] = true };
        if(value[\requireMeasured] == "false") { value[\requireMeasured] = false };
        if(value[\requireMeasured].notNil and: { [true, false].includes(value[\requireMeasured]).not }) { ^nil };
        ranges.keysValuesDo { |key, spec|
            var lo, hi, kind;
            if(key.isKindOf(String) and: {
                "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$".matchRegexp(key)
            } and: { spec.isKindOf(Dictionary) }) {
                lo = this.schemaNumber(spec["min"]); hi = this.schemaNumber(spec["max"]);
                kind = spec["type"];
                if(lo.notNil and: { hi.notNil and: { lo <= hi } } and: {
                    kind.isNil or: { kind == "number" or: { kind == "object" } }
                }) {
                    value[\ranges][key.asSymbol] = (min: lo, max: hi, type: kind);
                } { valid = false };
            } { valid = false };
        };
        ^if(valid) { value } { nil };
    }

    *valueAt { |map, path|
        var value = map;
        path.asString.split($.).do { |part|
            value = if(value.isKindOf(Dictionary)) { value[part.asSymbol] } { nil };
        };
        ^value;
    }

    *putAt { |map, path, value|
        var parts = path.asString.split($.), parent = map;
        (parts.size - 1).do { |i| parent = parent[parts[i].asSymbol] };
        parent[parts.last.asSymbol] = value;
    }

    *shapeValid { |map, contract|
        var dimensions = [\spectral_profile, \temporal_topology, \modulation_graph, \performance_response];
        if(map.isKindOf(Dictionary).not or: { contract.isKindOf(Dictionary).not }) { ^false };
        if(contract[\requiredKeys].isArray.not or: { contract[\ranges].isKindOf(Dictionary).not }) { ^false };
        ^contract[\requiredKeys].every { |key|
            var kind = (contract[\ranges][key] ? ())[\type];
            map.includesKey(key) and: {
                if(kind == "number") { this.finiteNumber(map[key]) } {
                    (dimensions.includes(key) or: { kind == "object" }).not or: { map[key].isKindOf(Dictionary) }
                }
            } and: {
                // Required traits need actual finite numeric structure even
                // without a declared range. Metadata counts may exceed one.
                this.validValue(map[key], checkBounds: false)
            }
        };
    }

    *validValue { |value, lo=0.0, hi=1.0, checkBounds=true|
        if(this.finiteNumber(value)) { ^checkBounds.not or: { value >= lo and: { value <= hi } } };
        if(value.isKindOf(Dictionary)) {
            ^value.notEmpty and: { value.keys.every { |key|
                if(key == \type and: { value[key].isKindOf(Symbol) or: { value[key].isKindOf(String) } }) {
                    true // descriptive categorical metadata is not a numeric leaf
                } { this.validValue(value[key], lo, hi, checkBounds) }
            } };
        };
        ^false;
    }

    *valueTypeValid { |value, kind|
        if(kind.isNil) { ^true };
        if(kind == "number") { ^this.finiteNumber(value) };
        if(kind == "object") { ^value.isKindOf(Dictionary) };
        ^false;
    }

    *validMeasurement { |map, threshold=0.85|
        var confidence, evidence;
        if(map.isKindOf(Dictionary).not or: { this.finiteNumber(threshold).not }) { ^false };
        confidence = map[\confidence]; evidence = map[\measurements];
        if(evidence.isKindOf(Dictionary).not) { ^false };
        if([\coherence, \entropy, \fidelity].any { |key| this.finiteNumber(evidence[key]).not }) { ^false };
        if(evidence[\coherence].inclusivelyBetween(0, 1).not or: {
            evidence[\entropy].inclusivelyBetween(0, 14).not or: { evidence[\fidelity].inclusivelyBetween(0, 1).not }
        }) { ^false };
        ^this.finiteNumber(confidence) and: {
            confidence >= threshold and: { confidence <= 1 and: {
                map[\provenance] == \measured and: { (confidence - evidence[\fidelity]).abs < 1e-6 }
            } }
        };
    }

    *validate { |map, contract, threshold=0.85|
        var valid = true;
        if(this.shapeValid(map, contract).not) { ^false };
        threshold = contract[\provenance_min_confidence] ? threshold;
        contract[\ranges].keysValuesDo { |path, spec|
            var value = this.valueAt(map, path);
            if(value.notNil and: {
                this.valueTypeValid(value, spec[\type]).not or: {
                    this.validValue(value, spec[\min], spec[\max]).not
                }
            }) { valid = false };
        };
        if(map[\confidence].notNil) {
            valid = valid and: { this.finiteNumber(map[\confidence]) and: {
                map[\confidence].inclusivelyBetween(threshold, 1)
            } };
        };
        if(contract[\requireMeasured] == true) { valid = valid and: { this.validMeasurement(map, threshold) } };
        ^valid;
    }

    *clipValue { |value, lo, hi|
        var copy;
        if(this.finiteNumber(value)) { ^value.clip(lo, hi) };
        if(value.isKindOf(Dictionary)) {
            copy = value.deepCopy;
            copy.keysValuesChange { |key, item| this.clipValue(item, lo, hi) };
            ^copy;
        };
        ^value;
    }

    *normalize { |map, contract|
        var result, valid = true;
        if(this.shapeValid(map, contract).not) { ^nil };
        result = map.deepCopy;
        contract[\ranges].keysValuesDo { |path, spec|
            var value = this.valueAt(result, path);
            if(value.notNil) {
                if(this.valueTypeValid(value, spec[\type]) and: {
                    this.validValue(value, spec[\min], spec[\max], false)
                }) {
                    this.putAt(result, path, this.clipValue(value, spec[\min], spec[\max]));
                } { valid = false };
            };
        };
        if(result != map and: { result[\provenance] == \measured }) {
            result[\provenance] = \proxy;
            result.removeAt(\measurements); result.removeAt(\confidence);
        };
        // Parent/child ranges can conflict. Never return a partially valid map.
        ^if(valid and: { this.validate(result, contract) }) { result } { nil };
    }
}
