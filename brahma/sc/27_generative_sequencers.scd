/*
  Phase 8: DAEMON Suite — Generative Sequencer Extensions
  ARBOR_VITAE (L-System/Fractal Sequencer),
  Extended Euclidean with accent patterns,
  Probability Matrix Sequencer
*/

(
// ==========================================
// LANGUAGE-SIDE: ARBOR_VITAE (L-System / Fractal Sequencer)
// ==========================================
// Lindenmayer system that converts string rewriting into musical sequences.
// Characters map to intervals; bracket notation provides push/pop pitch stacking.
// The generate method expands the axiom through N iterations, then converts
// the result string into a MIDI note sequence via the intervalMap.
~ARBOR_VITAE = { |axiom="F", rules=nil, iterations=3|
	(
		axiom: axiom,
		rules: rules ?? { IdentityDictionary[$F -> "F[+F]F[-F]F"] },
		iterations: iterations,
		result: nil,
		noteSequence: nil,
		pos: 0,

		// Character to musical interval mapping
		intervalMap: IdentityDictionary[
			$F -> 0, $G -> 2, $+ -> 1, $- -> -1,
			$[ -> 5, $] -> -5, $A -> 3, $B -> 4
		],

		generate: { |self|
			var str = self[\axiom];
			self[\iterations].clip(1, 8).do({
				var out = "";
				str.do({ |c|
					var rep = self[\rules][c];
					out = out ++ (rep ?? { c.asString });
				});
				str = out;
			});
			self[\result] = str;

			// Convert L-system string to note sequence
			var note = 60;
			var stack = List.new;
			self[\noteSequence] = List.new;

			str.do({ |c|
				var interval = self[\intervalMap][c];
				// Push/pop stack for bracket notation
				if(c == $[) { stack.add(note) };
				if(c == $]) { if(stack.size > 0) { note = stack.pop } };
				if(interval.notNil) {
					note = (note + interval).clip(24, 108);
					self[\noteSequence].add(note);
				};
			});

			// Safety: ensure at least one note exists
			if(self[\noteSequence].size == 0) { self[\noteSequence].add(60) };
			"ARBOR_VITAE: Generated % notes from % chars".format(
				self[\noteSequence].size, str.size
			).postln;
		},

		next: { |self|
			if(self[\noteSequence].isNil) { self.generate };
			var n = self[\noteSequence][self[\pos]];
			self[\pos] = (self[\pos] + 1) % self[\noteSequence].size;
			n;
		},

		cv: { |self|
			// Normalize MIDI note to 0-1 range (24-108 → 0.0-1.0)
			(self.next - 24) / 84;
		},

		reset: { |self| self[\pos] = 0; },

		setRule: { |self, char, replacement|
			self[\rules][char] = replacement;
			// Invalidate cached sequence so next access regenerates
			self[\noteSequence] = nil;
			self[\result] = nil;
		},

		setIterations: { |self, n|
			self[\iterations] = n.clip(1, 8);
			self[\noteSequence] = nil;
			self[\result] = nil;
		},

		setAxiom: { |self, ax|
			self[\axiom] = ax;
			self[\noteSequence] = nil;
			self[\result] = nil;
		}
	);
};

// ==========================================
// LANGUAGE-SIDE: EXTENDED EUCLIDEAN WITH ACCENTS
// ==========================================
// Euclidean rhythm generator with a secondary accent layer.
// The accent pattern is itself a Euclidean distribution within
// the hit positions, creating weighted velocity patterns.
// gate() returns 0/1, accent() returns 0/1 for accented hits,
// velocity() returns 1.0 (accent) or 0.6 (normal hit).
~DAEMON_EUCLIDEAN_EXT = { |length=16, hits=4, accents=2, rotation=0|
	(
		length: length,
		hits: hits,
		accents: accents,
		rotation: rotation,
		pattern: nil,
		accentPattern: nil,
		pos: 0,

		generate: { |self|
			// Bresenham Euclidean rhythm algorithm
			self[\pattern] = Array.fill(self[\length], { |i|
				((i * self[\hits]) % self[\length]) < self[\hits];
			}).rotate(self[\rotation].asInteger);

			// Accent pattern: Euclidean distribution within hit positions
			var hitPositions = List.new;
			self[\pattern].do({ |v, i|
				if(v) { hitPositions.add(i) };
			});

			self[\accentPattern] = Array.fill(self[\length], { false });

			if(hitPositions.size > 0) {
				var numAccents = self[\accents].clip(0, hitPositions.size);
				var accPat = Array.fill(hitPositions.size, { |i|
					((i * numAccents) % hitPositions.size) < numAccents;
				});
				accPat.do({ |isAccent, i|
					if(isAccent) {
						self[\accentPattern][hitPositions[i]] = true;
					};
				});
			};

			"DAEMON_EUCLIDEAN_EXT: Generated E(%, %) + % accents, rot=%".format(
				self[\hits], self[\length], self[\accents], self[\rotation]
			).postln;
		},

		advance: { |self|
			if(self[\pattern].isNil) { self.generate };
			self[\pos] = (self[\pos] + 1) % self[\length];
		},

		gate: { |self|
			if(self[\pattern].isNil) { self.generate };
			self[\pattern][self[\pos]].asInteger;
		},

		accent: { |self|
			if(self[\accentPattern].isNil) { self.generate };
			self[\accentPattern][self[\pos]].asInteger;
		},

		velocity: { |self|
			if(self.accent > 0) { 1.0 } { 0.6 };
		},

		setParams: { |self, length, hits, accents, rotation|
			self[\length] = length.clip(1, 64);
			self[\hits] = hits.clip(0, self[\length]);
			self[\accents] = accents.clip(0, self[\hits]);
			self[\rotation] = rotation.clip(0, self[\length] - 1);
			self.generate;
		},

		reset: { |self| self[\pos] = 0; }
	);
};

// ==========================================
// LANGUAGE-SIDE: PROBABILITY MATRIX SEQUENCER
// ==========================================
// A rows x cols grid where each cell holds a probability (0.0-1.0).
// On each step, the sequencer advances the column position and
// rolls a coin for each row — rows that pass produce a gate.
// Useful for generative drum programming where each row is a voice
// and each column is a time step.
~DAEMON_PROB_MATRIX = { |rows=8, cols=16|
	(
		matrix: Array.fill(rows, { Array.fill(cols, { 0.0 }) }),
		rows: rows,
		cols: cols,
		pos: 0,

		setCell: { |self, row, col, probability|
			if(row < self[\rows] and: { col < self[\cols] }) {
				self[\matrix][row.asInteger][col.asInteger] = probability.clip(0, 1);
			};
		},

		getCell: { |self, row, col|
			if(row < self[\rows] and: { col < self[\cols] }) {
				self[\matrix][row.asInteger][col.asInteger];
			} { 0.0 };
		},

		advance: { |self|
			self[\pos] = (self[\pos] + 1) % self[\cols];
		},

		getActiveRows: { |self|
			// Returns an array of 0/1 for each row at current position.
			// Each cell's probability is evaluated via coin flip.
			self[\rows].collect({ |i|
				self[\matrix][i][self[\pos]].coin.asInteger;
			});
		},

		getColumn: { |self|
			// Returns raw probabilities for current column (no coin flip)
			self[\rows].collect({ |i|
				self[\matrix][i][self[\pos]];
			});
		},

		// Fill a row with a pattern (array of probabilities)
		setRow: { |self, row, pattern|
			if(row < self[\rows]) {
				self[\cols].do({ |col|
					self[\matrix][row.asInteger][col] = pattern.wrapAt(col).clip(0, 1);
				});
			};
		},

		// Randomize entire matrix with probability density
		randomize: { |self, density=0.3|
			self[\rows].do({ |r|
				self[\cols].do({ |c|
					self[\matrix][r][c] = if(density.coin) { rrand(0.3, 1.0) } { 0.0 };
				});
			});
			"DAEMON_PROB_MATRIX: Randomized %x% with density %".format(
				self[\rows], self[\cols], density
			).postln;
		},

		clear: { |self|
			self[\rows].do({ |r|
				self[\cols].do({ |c|
					self[\matrix][r][c] = 0.0;
				});
			});
		},

		reset: { |self| self[\pos] = 0; }
	);
};

// ==========================================
// SYNTHDEF: PROBABILITY GATE (server-side coin flip gate)
// ==========================================
// Passes or blocks triggers based on probability.
// Useful as a server-side thinning filter for clock signals.
SynthDef(\daemon_prob_gate, {
	|trigBus=0, outBus=0, probability=1.0|

	var trig, pass;
	trig = In.kr(trigBus, 1);
	pass = TIRand.kr(0, 1000, trig) < (probability.clip(0, 1) * 1000);
	Out.kr(outBus, trig * pass);
}).add;


// ==========================================
// GLOBAL INSTANCES DICTIONARY
// ==========================================
~DAEMON_SEQ_INSTANCES = IdentityDictionary.new;

// ==========================================
// OSC RESPONDERS: ARBOR_VITAE (L-System Sequencer)
// ==========================================
OSCdef(\arbor_create, { |msg|
	var name = msg[1].asSymbol;
	var axiom = (msg[2] ? "F").asString;
	var iterations = (msg[3] ? 3).asInteger;
	var inst = ~ARBOR_VITAE.(axiom, nil, iterations);
	inst.generate;
	~DAEMON_SEQ_INSTANCES[name] = [\arbor, inst];
	"ARBOR_VITAE: Created '%' (axiom='%', iter=%)".format(name, axiom, iterations).postln;
}, "/arbor/create");

OSCdef(\arbor_next, { |msg|
	var name = msg[1].asSymbol;
	var outBusIdx = msg[2].asInteger;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \arbor }) {
		var inst = entry[1];
		var bus = Bus(\control, outBusIdx, 1, s);
		bus.set(inst.cv);
	};
}, "/arbor/next");

OSCdef(\arbor_set_rule, { |msg|
	// /arbor/set_rule name char replacement
	var name = msg[1].asSymbol;
	var char = msg[2].asString[0]; // first character
	var replacement = msg[3].asString;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \arbor }) {
		entry[1].setRule(char, replacement);
		"ARBOR_VITAE: '%' rule % -> %".format(name, char, replacement).postln;
	};
}, "/arbor/set_rule");

OSCdef(\arbor_regenerate, { |msg|
	var name = msg[1].asSymbol;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \arbor }) {
		entry[1].generate;
	};
}, "/arbor/regenerate");

OSCdef(\arbor_reset, { |msg|
	var name = msg[1].asSymbol;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \arbor }) {
		entry[1].reset;
	};
}, "/arbor/reset");

// ==========================================
// OSC RESPONDERS: EXTENDED EUCLIDEAN
// ==========================================
OSCdef(\deuc_create, { |msg|
	var name = msg[1].asSymbol;
	var length = (msg[2] ? 16).asInteger;
	var hits = (msg[3] ? 4).asInteger;
	var accents = (msg[4] ? 2).asInteger;
	var rotation = (msg[5] ? 0).asInteger;
	var inst = ~DAEMON_EUCLIDEAN_EXT.(length, hits, accents, rotation);
	inst.generate;
	~DAEMON_SEQ_INSTANCES[name] = [\euclidean, inst];
	"DAEMON_EUCLIDEAN_EXT: Created '%'".format(name).postln;
}, "/daemon/euclidean/create");

OSCdef(\deuc_advance, { |msg|
	var name = msg[1].asSymbol;
	var gateBusIdx = msg[2].asInteger;
	var accentBusIdx = msg[3].asInteger;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \euclidean }) {
		var inst = entry[1];
		inst.advance;
		var gateBus = Bus(\control, gateBusIdx, 1, s);
		var accentBus = Bus(\control, accentBusIdx, 1, s);
		gateBus.set(inst.gate);
		accentBus.set(inst.velocity);
	};
}, "/daemon/euclidean/advance");

OSCdef(\deuc_set, { |msg|
	var name = msg[1].asSymbol;
	var length = msg[2].asInteger;
	var hits = msg[3].asInteger;
	var accents = msg[4].asInteger;
	var rotation = (msg[5] ? 0).asInteger;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \euclidean }) {
		entry[1].setParams(length, hits, accents, rotation);
	};
}, "/daemon/euclidean/set");

OSCdef(\deuc_reset, { |msg|
	var name = msg[1].asSymbol;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \euclidean }) {
		entry[1].reset;
	};
}, "/daemon/euclidean/reset");

// ==========================================
// OSC RESPONDERS: PROBABILITY MATRIX SEQUENCER
// ==========================================
OSCdef(\probmatrix_create, { |msg|
	var name = msg[1].asSymbol;
	var rows = (msg[2] ? 8).asInteger;
	var cols = (msg[3] ? 16).asInteger;
	var inst = ~DAEMON_PROB_MATRIX.(rows, cols);
	~DAEMON_SEQ_INSTANCES[name] = [\probmatrix, inst];
	"DAEMON_PROB_MATRIX: Created '%' (%x%)".format(name, rows, cols).postln;
}, "/daemon/probmatrix/create");

OSCdef(\probmatrix_set_cell, { |msg|
	// /daemon/probmatrix/set_cell name row col probability
	var name = msg[1].asSymbol;
	var row = msg[2].asInteger;
	var col = msg[3].asInteger;
	var prob = msg[4].asFloat;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \probmatrix }) {
		entry[1].setCell(row, col, prob);
	};
}, "/daemon/probmatrix/set_cell");

OSCdef(\probmatrix_set_row, { |msg|
	// /daemon/probmatrix/set_row name row p0 p1 p2 ...
	var name = msg[1].asSymbol;
	var row = msg[2].asInteger;
	var pattern = msg[3..].collect({ |v| v.asFloat });
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \probmatrix }) {
		entry[1].setRow(row, pattern);
	};
}, "/daemon/probmatrix/set_row");

OSCdef(\probmatrix_advance, { |msg|
	// /daemon/probmatrix/advance name gateBus0 gateBus1 ...
	var name = msg[1].asSymbol;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \probmatrix }) {
		var inst = entry[1];
		inst.advance;
		var activeRows = inst.getActiveRows;
		// Write gate values to specified buses
		var busIndices = msg[2..];
		activeRows.do({ |gate, i|
			if(i < busIndices.size) {
				var bus = Bus(\control, busIndices[i].asInteger, 1, s);
				bus.set(gate);
			};
		});
	};
}, "/daemon/probmatrix/advance");

OSCdef(\probmatrix_randomize, { |msg|
	var name = msg[1].asSymbol;
	var density = (msg[2] ? 0.3).asFloat;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \probmatrix }) {
		entry[1].randomize(density);
	};
}, "/daemon/probmatrix/randomize");

OSCdef(\probmatrix_clear, { |msg|
	var name = msg[1].asSymbol;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \probmatrix }) {
		entry[1].clear;
	};
}, "/daemon/probmatrix/clear");

OSCdef(\probmatrix_reset, { |msg|
	var name = msg[1].asSymbol;
	var entry = ~DAEMON_SEQ_INSTANCES[name];
	if(entry.notNil and: { entry[0] == \probmatrix }) {
		entry[1].reset;
	};
}, "/daemon/probmatrix/reset");

"--- BRAHMA: DAEMON Generative Sequencers Online (4 modules) ---".postln;
)
