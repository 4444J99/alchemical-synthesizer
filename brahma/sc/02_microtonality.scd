/*
  Phase 0A: Microtonality System
  Global tuning registry, BrahmaScale integration, OSC control
*/

(
// Initialize default scale (12-TET)
~BRAHMA_TUNING[\currentScale] = BrahmaScale.equalTemperament12;
~BRAHMA_TUNING[\rootHz] = 440.0;
~BRAHMA_TUNING[\transpose] = 0;

// Available scale library (pre-loaded for quick switching)
~BRAHMA_TUNING[\library] = Dictionary.new;
~BRAHMA_TUNING[\library].putAll((
    \equal12:      BrahmaScale.equalTemperament12,
    \just:         BrahmaScale.justIntonation,
    \pythagorean:  BrahmaScale.pythagorean,
    \bohlenPierce: BrahmaScale.bohlenPierce,
    \carlosAlpha:  BrahmaScale.carlosAlpha,
    \carlosBeta:   BrahmaScale.carlosBeta,
    \carlosGamma:  BrahmaScale.carlosGamma,
    \slendro:      BrahmaScale.gamelanSlendro,
    \pelog:        BrahmaScale.gamelanPelog,
    \partch43:     BrahmaScale.partch43,
    \quarterTone:  BrahmaScale.quarterTone,
    \major:        BrahmaScale.majorScale,
    \minor:        BrahmaScale.minorScale,
    \pentatonic:   BrahmaScale.pentatonicMajor,
    \chromatic:    BrahmaScale.chromatic,
    \wholeTone:    BrahmaScale.wholeTone
));

// Helper: convert degree to freq using current global tuning
~BRAHMA_TUNING[\degreeToFreq] = { |self, degree, octave=4|
    var freq = self[\currentScale].degreeToFreq(degree, octave, self[\rootHz]);
    // Apply transpose
    freq * (2 ** (self[\transpose] / 12));
};

// Helper: quantize arbitrary Hz to current scale
~BRAHMA_TUNING[\quantize] = { |self, freqHz|
    self[\currentScale].quantize(freqHz, self[\rootHz]);
};

// Helper: load a Scala .scl file and add to library
~BRAHMA_TUNING[\loadScala] = { |self, path, name|
    var scale = BrahmaScale.fromScala(path);
    if(scale.notNil) {
        self[\library].put(name.asSymbol, scale);
        "TUNING: Loaded Scala file '%' as '%'".format(path, name).postln;
    };
    scale;
};

// Helper: set scale by library name
~BRAHMA_TUNING[\setScale] = { |self, name|
    var scale = self[\library][name.asSymbol];
    if(scale.notNil) {
        self[\currentScale] = scale;
        "TUNING: Scale set to '%' (% degrees)".format(name, scale.size).postln;
    } {
        "TUNING: Scale '%' not found in library".format(name).warn;
    };
};

// ==========================================
// OSC RESPONDERS
// ==========================================

// /brahma/tuning/scale <name:string>
// Switch to a scale from the library
OSCdef(\brahma_tuning_scale, { |msg|
    var name = msg[1].asSymbol;
    ~BRAHMA_TUNING.setScale(name);
    ~VISUAL_CORTEX.target.sendMsg("/brahma/tuning/state",
        ~BRAHMA_TUNING[\currentScale].name,
        ~BRAHMA_TUNING[\rootHz],
        ~BRAHMA_TUNING[\transpose]);
}, "/brahma/tuning/scale");

// /brahma/tuning/root <hz:float>
// Set root frequency
OSCdef(\brahma_tuning_root, { |msg|
    ~BRAHMA_TUNING[\rootHz] = msg[1].asFloat.clip(20, 20000);
    "TUNING: Root set to % Hz".format(~BRAHMA_TUNING[\rootHz]).postln;
    ~VISUAL_CORTEX.target.sendMsg("/brahma/tuning/state",
        ~BRAHMA_TUNING[\currentScale].name,
        ~BRAHMA_TUNING[\rootHz],
        ~BRAHMA_TUNING[\transpose]);
}, "/brahma/tuning/root");

// /brahma/tuning/transpose <semitones:int>
// Set global transpose offset
OSCdef(\brahma_tuning_transpose, { |msg|
    ~BRAHMA_TUNING[\transpose] = msg[1].asInteger.clip(-48, 48);
    "TUNING: Transpose set to % semitones".format(~BRAHMA_TUNING[\transpose]).postln;
    ~VISUAL_CORTEX.target.sendMsg("/brahma/tuning/state",
        ~BRAHMA_TUNING[\currentScale].name,
        ~BRAHMA_TUNING[\rootHz],
        ~BRAHMA_TUNING[\transpose]);
}, "/brahma/tuning/transpose");

// /brahma/tuning/loadScala <path:string> <name:string>
// Load a Scala .scl file
OSCdef(\brahma_tuning_loadScala, { |msg|
    ~BRAHMA_TUNING.loadScala(msg[1].asString, msg[2].asString);
}, "/brahma/tuning/loadScala");

// /brahma/tuning/ntet <n:int>
// Create N-TET and switch to it
OSCdef(\brahma_tuning_ntet, { |msg|
    var n = msg[1].asInteger.clip(1, 128);
    var scale = BrahmaScale.equalTemperament(n);
    var name = (n.asString ++ "tet").asSymbol;
    ~BRAHMA_TUNING[\library].put(name, scale);
    ~BRAHMA_TUNING[\currentScale] = scale;
    "TUNING: Created and switched to %-TET".format(n).postln;
}, "/brahma/tuning/ntet");

// /brahma/tuning/ratios <name:string> <ratios:float...>
// Create custom scale from ratios
OSCdef(\brahma_tuning_ratios, { |msg|
    var name = msg[1].asString;
    var ratios = msg[2..].collect(_.asFloat);
    var scale = BrahmaScale.fromRatios(name, ratios);
    ~BRAHMA_TUNING[\library].put(name.asSymbol, scale);
    ~BRAHMA_TUNING[\currentScale] = scale;
    "TUNING: Custom scale '%' created with % degrees".format(name, ratios.size).postln;
}, "/brahma/tuning/ratios");

"--- BRAHMA: Microtonality System Online (% scales loaded) ---".format(~BRAHMA_TUNING[\library].size).postln;
)
