/*
  BrahmaScale: Microtonality System
  Scale/tuning abstraction for the Brahma Meta-Rack

  Stores scales as ratio arrays, provides factory methods for
  common tuning systems, Scala .scl file parsing, and per-voice
  pitch utilities.
*/

BrahmaScale {
    var <name;
    var <ratios;       // Array of frequency ratios (1.0 = root)
    var <octaveRatio;  // Ratio for octave equivalence (usually 2.0)
    var <description;

    *new { |name, ratios, octaveRatio=2.0, description=""|
        ^super.newCopyArgs(name, ratios, octaveRatio, description);
    }

    // Number of degrees in this scale
    size { ^ratios.size }

    // Convert scale degree + octave to frequency
    degreeToFreq { |degree, octave=4, rootHz=440.0|
        var numDegrees = ratios.size;
        var octaveOffset, degreeInScale, ratio;

        // Handle negative degrees and octave wrapping
        octaveOffset = degree.div(numDegrees);
        degreeInScale = degree % numDegrees;
        if(degreeInScale < 0) {
            degreeInScale = degreeInScale + numDegrees;
            octaveOffset = octaveOffset - 1;
        };

        ratio = ratios[degreeInScale];
        ^rootHz * ratio * (octaveRatio ** (octave + octaveOffset - 4));
    }

    // Quantize arbitrary Hz to nearest scale degree
    quantize { |freqHz, rootHz=440.0|
        var bestDist = inf, bestFreq = freqHz;

        // Search across nearby octaves
        (-2..8).do({ |oct|
            ratios.size.do({ |deg|
                var candidate = this.degreeToFreq(deg, oct, rootHz);
                var dist = (candidate - freqHz).abs;
                if(dist < bestDist) {
                    bestDist = dist;
                    bestFreq = candidate;
                };
            });
        });

        ^bestFreq;
    }

    // Return cents deviation table from 12-TET
    centsTable {
        ^ratios.collect({ |r| (1200 * r.log2).round(0.01) });
    }

    printOn { |stream|
        stream << "BrahmaScale(" << name << ", " << ratios.size << " degrees)";
    }

    // ==========================================
    // FACTORY METHODS — Standard Tuning Systems
    // ==========================================

    *equalTemperament12 {
        ^this.new("12-TET",
            Array.fill(12, { |i| 2 ** (i / 12) }),
            2.0,
            "Standard 12-tone equal temperament"
        );
    }

    *justIntonation {
        ^this.new("Just Intonation",
            [1, 16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 9/5, 15/8],
            2.0,
            "5-limit just intonation (Ptolemy)"
        );
    }

    *pythagorean {
        ^this.new("Pythagorean",
            [1, 256/243, 9/8, 32/27, 81/64, 4/3, 729/512, 3/2, 128/81, 27/16, 16/9, 243/128],
            2.0,
            "Pythagorean 3-limit tuning"
        );
    }

    *bohlenPierce {
        ^this.new("Bohlen-Pierce",
            Array.fill(13, { |i| 3 ** (i / 13) }),
            3.0,
            "Bohlen-Pierce tritave-based scale (13 steps per 3:1)"
        );
    }

    *carlosAlpha {
        // Wendy Carlos Alpha: 78 cents per step
        ^this.new("Carlos Alpha",
            Array.fill(15, { |i| 2 ** (i * 0.065) }),
            2.0,
            "Wendy Carlos Alpha (~78 cents/step)"
        );
    }

    *carlosBeta {
        // Wendy Carlos Beta: 63.8 cents per step
        ^this.new("Carlos Beta",
            Array.fill(19, { |i| 2 ** (i * 0.05317) }),
            2.0,
            "Wendy Carlos Beta (~63.8 cents/step)"
        );
    }

    *carlosGamma {
        // Wendy Carlos Gamma: 35.1 cents per step
        ^this.new("Carlos Gamma",
            Array.fill(34, { |i| 2 ** (i * 0.02925) }),
            2.0,
            "Wendy Carlos Gamma (~35.1 cents/step)"
        );
    }

    *gamelanSlendro {
        ^this.new("Slendro",
            [1, 1.125, 1.265, 1.5, 1.685],
            2.0,
            "Javanese Gamelan Slendro (5-tone)"
        );
    }

    *gamelanPelog {
        ^this.new("Pelog",
            [1, 1.067, 1.185, 1.333, 1.414, 1.580, 1.778],
            2.0,
            "Javanese Gamelan Pelog (7-tone)"
        );
    }

    *partch43 {
        // Harry Partch 43-tone scale (11-limit just intonation)
        var rats = [
            1, 81/80, 33/32, 21/20, 16/15, 12/11, 11/10, 10/9, 9/8, 8/7,
            7/6, 32/27, 6/5, 11/9, 5/4, 14/11, 9/7, 21/16, 4/3, 27/20,
            11/8, 7/5, 10/7, 16/11, 40/27, 3/2, 32/21, 14/9, 11/7, 8/5,
            18/11, 5/3, 27/16, 12/7, 7/4, 16/9, 9/5, 20/11, 11/6, 15/8,
            40/21, 64/33, 160/81
        ];
        ^this.new("Partch 43", rats, 2.0,
            "Harry Partch 43-tone 11-limit just intonation"
        );
    }

    *quarterTone {
        ^this.new("Quarter-Tone",
            Array.fill(24, { |i| 2 ** (i / 24) }),
            2.0,
            "24-tone quarter-tone equal temperament"
        );
    }

    // N-TET (arbitrary equal temperament)
    *equalTemperament { |n=12|
        ^this.new(n.asString ++ "-TET",
            Array.fill(n, { |i| 2 ** (i / n) }),
            2.0,
            n.asString ++ "-tone equal temperament"
        );
    }

    // User-defined from ratio array
    *fromRatios { |name, ratios, octaveRatio=2.0|
        ^this.new(name, ratios, octaveRatio, "User-defined scale");
    }

    // ==========================================
    // SCALA .scl FILE PARSER
    // ==========================================
    *fromScala { |path|
        var lines, name, numNotes, ratios, octaveRatio;
        var file = File(path, "r");

        if(file.isOpen.not) {
            ("BrahmaScale: Cannot open Scala file: " ++ path).warn;
            ^nil;
        };

        lines = List.new;
        file.readAllString.split($\n).do({ |line|
            var trimmed = line.stripWhiteSpace;
            // Skip comments (lines starting with !)
            if(trimmed.size > 0 and: { trimmed[0] != $! }) {
                lines.add(trimmed);
            };
        });
        file.close;

        if(lines.size < 2) {
            "BrahmaScale: Invalid Scala file format".warn;
            ^nil;
        };

        name = lines[0];
        numNotes = lines[1].asInteger;

        ratios = [1.0]; // Root is always 1.0

        (2..(numNotes + 1)).do({ |i|
            if(i < lines.size) {
                var entry = lines[i].stripWhiteSpace;
                var ratio;

                if(entry.contains("/")) {
                    // Ratio notation: e.g. "3/2"
                    var parts = entry.split($/);
                    ratio = parts[0].asFloat / parts[1].asFloat;
                } {
                    if(entry.contains(".")) {
                        // Cents notation: e.g. "701.955"
                        ratio = 2 ** (entry.asFloat / 1200);
                    } {
                        // Integer (treat as cents)
                        ratio = 2 ** (entry.asFloat / 1200);
                    };
                };

                ratios = ratios.add(ratio);
            };
        });

        // Last ratio is the octave equivalence
        if(ratios.size > 1) {
            octaveRatio = ratios.last;
            ratios = ratios.copyRange(0, ratios.size - 2);
        } {
            octaveRatio = 2.0;
        };

        ^this.new(name, ratios, octaveRatio, "Imported from Scala: " ++ path);
    }

    // ==========================================
    // COMMON SUBSETS (modes, pentatonics)
    // ==========================================

    *majorScale {
        // Major scale degrees from 12-TET: 0,2,4,5,7,9,11
        var base = this.equalTemperament12;
        var degrees = [0, 2, 4, 5, 7, 9, 11];
        ^this.new("Major",
            degrees.collect({ |d| base.ratios[d] }),
            2.0,
            "Major scale (Ionian mode)"
        );
    }

    *minorScale {
        var base = this.equalTemperament12;
        var degrees = [0, 2, 3, 5, 7, 8, 10];
        ^this.new("Natural Minor",
            degrees.collect({ |d| base.ratios[d] }),
            2.0,
            "Natural minor scale (Aeolian mode)"
        );
    }

    *pentatonicMajor {
        var base = this.equalTemperament12;
        var degrees = [0, 2, 4, 7, 9];
        ^this.new("Pentatonic Major",
            degrees.collect({ |d| base.ratios[d] }),
            2.0,
            "Major pentatonic scale"
        );
    }

    *chromatic {
        ^this.equalTemperament12;
    }

    *wholeTone {
        var base = this.equalTemperament12;
        var degrees = [0, 2, 4, 6, 8, 10];
        ^this.new("Whole Tone",
            degrees.collect({ |d| base.ratios[d] }),
            2.0,
            "Whole tone scale"
        );
    }
}
