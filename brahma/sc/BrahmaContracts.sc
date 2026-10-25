/* JSON contract handling shared by audio and non-audio trait maps. */
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

    *load { |path|
        var value, valid = true;
        if(File.exists(path).not) { ^nil };
        try { value = this.symbolize(path.parseJSONFile) } { |err| err.reportError; value = nil };
        if(value.isKindOf(Dictionary).not) { ^nil };
        if(value[\name].isNil or: { value[\requiredKeys].isArray.not }) { ^nil };
        if(value[\requiredKeys].isEmpty) { ^nil };
        value[\requiredKeys] = value[\requiredKeys].collect(_.asSymbol);
        // SC's parseJSON aliases parseYAML and returns scalar strings. Decode
        // typed schema fields explicitly; preserve labels and organism names.
        if(value[\requireMeasured] == "true") { value[\requireMeasured] = true };
        if(value[\requireMeasured] == "false") { value[\requireMeasured] = false };
        if(value[\requireMeasured].notNil and: { [true, false].includes(value[\requireMeasured]).not }) { ^nil };
        (value[\ranges] ? ()).values.do { |spec|
            [\min, \max].do { |key|
                if(spec[key].notNil) {
                    spec[key] = this.schemaNumber(spec[key]);
                    if(spec[key].isNil) { valid = false };
                };
            };
            if(spec[\min].notNil and: { spec[\max].notNil and: { spec[\min] > spec[\max] } }) { valid = false };
        };
        if(valid.not) { ^nil };
        ^value;
    }

    *schemaNumber { |value|
        var number;
        if(this.finiteNumber(value)) { ^value };
        if(value.isKindOf(String) and: { "^[-+]?[0-9]*[.]?[0-9]+([eE][-+]?[0-9]+)?$".matchRegexp(value) }) {
            number = value.asFloat;
            if(this.finiteNumber(number)) { ^number };
        };
        ^nil;
    }

    *finiteNumber { |value|
        ^value.isNumber and: { value.isNaN.not and: { value.abs < inf } };
    }

    *validValue { |value, lo=0.0, hi=1.0|
        var valid = true;
        if(value.isNumber) { ^this.finiteNumber(value) and: { value >= lo and: { value <= hi } } };
        if(value.isKindOf(Dictionary)) {
            value.keysValuesDo { |key, item|
                if(key == \type and: { item.isKindOf(Symbol) or: { item.isKindOf(String) } }) {
                    // Named descriptive types are not numeric trait values.
                } { valid = valid and: { this.validValue(item, lo, hi) } };
            };
            ^value.notEmpty and: { valid };
        };
        if(value.isArray) { ^value.notEmpty and: { value.every { |item| this.validValue(item, lo, hi) } } };
        ^false;
    }

    *validMeasurement { |map, threshold=0.85|
        var confidence, provenance, evidence;
        if(map.isKindOf(Dictionary).not) { ^false };
        confidence = map[\confidence]; provenance = map[\provenance];
        evidence = map[\measurements];
        if(evidence.isKindOf(Dictionary).not) { ^false };
        if([\coherence, \entropy, \fidelity].any { |key| this.finiteNumber(evidence[key]).not }) { ^false };
        if(evidence[\coherence].inclusivelyBetween(0, 1).not or: {
            evidence[\entropy].inclusivelyBetween(0, 12).not or: { evidence[\fidelity].inclusivelyBetween(0, 1).not }
        }) { ^false };
        ^this.finiteNumber(confidence) and: {
            confidence >= threshold and: { confidence <= 1 and: {
                provenance == \measured and: { (confidence - evidence[\fidelity]).abs < 1e-6 }
            } }
        };
    }

    *validate { |map, contract, threshold=0.85|
        var valid = true, ranges;
        if(map.isKindOf(Dictionary).not or: { contract.isNil }) { ^false };
        ranges = contract[\ranges] ? ();
        contract[\requiredKeys].do { |key|
            var spec = ranges[key] ? ();
            if(spec[\type] == "number" and: { this.finiteNumber(map[key]).not }) { valid = false };
            if(map.includesKey(key).not or: {
                this.validValue(map[key], spec[\min] ? 0.0, spec[\max] ? 1.0).not
            }) { valid = false };
        };
        if(map[\confidence].notNil) {
            if(this.finiteNumber(map[\confidence]).not) { ^false };
            valid = valid and: { map[\confidence] >= threshold and: { map[\confidence] <= 1 } };
        };
        if(contract[\requireMeasured] == true) { valid = valid and: { this.validMeasurement(map, threshold) } };
        ^valid;
    }

    *clipValue { |value, lo, hi|
        if(value.isNumber) { ^value.clip(lo, hi) };
        if(value.isKindOf(Dictionary)) {
            ^value.collect { |item| this.clipValue(item, lo, hi) };
        };
        if(value.isArray) { ^value.collect { |item| this.clipValue(item, lo, hi) } };
        ^value;
    }

    *normalize { |map, contract|
        var result, ranges;
        if(map.isKindOf(Dictionary).not or: { contract.isNil }) { ^nil };
        result = map.deepCopy; ranges = contract[\ranges] ? ();
        contract[\requiredKeys].do { |key|
            var spec = ranges[key] ? ();
            if(result.includesKey(key)) { result[key] = this.clipValue(result[key], spec[\min] ? 0.0, spec[\max] ? 1.0) };
        };
        ^result;
    }
}
