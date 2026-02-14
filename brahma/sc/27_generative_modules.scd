/*
  Phase 8: DAEMON Suite — Generative Modules
  DAEMON_MACHINA (Turing Machine), MOIRAI (Markov Chain),
  GENESIS (Cellular Automata), TYCHE (Bernoulli Gates),
  TRIVIUM (Logic/Counters), SERPENS (Self-Patching Templates)
*/

(
// ==========================================
// SYNTHDEF: TURING MACHINE (audio-rate shift register)
// ==========================================
// Audio-rate shift-register CV/gate generator.
// On each trigger: register shifts, LSB flips with probability.
// CV = lower 8 bits normalized to 0-1. Gate = LSB.
SynthDef(\daemon_turing, {
	|outBusCV=0, outBusGate=1, trigBus=0, bits=8, probability=0.5|

	var trig, count, register_val, cv, gate, flip;

	trig = In.kr(trigBus, 1);

	// PulseCount tracks total triggers for deterministic register state
	count = PulseCount.kr(trig);

	// Simulate shift register via modulo arithmetic on pulse count.
	// Each bit position is derived from count shifted right by position.
	// The probability controls whether the new bit is random or preserves pattern.
	flip = TIRand.kr(0, 1000, trig) < (probability.clip(0, 1) * 1000);

	// Build register value: combine count-derived bits with stochastic injection.
	// Use count as a base pattern, XOR with random flip to inject mutation.
	register_val = (count + (flip * TIRand.kr(0, 255, trig))) % 256;

	// CV output: lower 8 bits → 0.0 to 1.0
	cv = register_val / 255.0;

	// Gate output: LSB
	gate = register_val % 2;

	Out.kr(outBusCV, cv);
	Out.kr(outBusGate, gate);
}).add;

// ==========================================
// SYNTHDEF: BERNOULLI CASCADE (3-level probability routing tree)
// ==========================================
// Input trigger → level 1 (prob1) → A or B.
// A → level 2 (prob2) → out1 or out2.
// B → level 3 (prob3) → out3 or out4.
// Creates weighted probability trees from a single trigger.
SynthDef(\daemon_bernoulli_cascade, {
	|inBus=0, outBus1=0, outBus2=1, outBus3=2, outBus4=3,
	 prob1=0.5, prob2=0.5, prob3=0.5|

	var trig, coin1, coinA, coinB;
	var branchA, branchB;

	trig = In.kr(inBus, 1);

	// Level 1: route to branch A or B
	coin1 = TIRand.kr(0, 1000, trig) < (prob1.clip(0, 1) * 1000);
	branchA = trig * coin1;
	branchB = trig * (1 - coin1);

	// Level 2: branch A → out1 or out2
	coinA = TIRand.kr(0, 1000, branchA) < (prob2.clip(0, 1) * 1000);
	Out.kr(outBus1, branchA * coinA);
	Out.kr(outBus2, branchA * (1 - coinA));

	// Level 3: branch B → out3 or out4
	coinB = TIRand.kr(0, 1000, branchB) < (prob3.clip(0, 1) * 1000);
	Out.kr(outBus3, branchB * coinB);
	Out.kr(outBus4, branchB * (1 - coinB));
}).add;

// ==========================================
// SYNTHDEF: FLIP-FLOP (toggle on trigger)
// ==========================================
// Toggles output between 0 and 1 on each input trigger.
// Reset input forces output back to 0.
SynthDef(\daemon_flipflop, {
	|inBus=0, outBus=0, resetBus=0|

	var trig, reset, state;

	trig = In.kr(inBus, 1);
	reset = In.kr(resetBus, 1);

	// ToggleFF toggles on each trigger; reset clears it
	state = ToggleFF.kr(trig);
	// Apply reset: if reset fires, force state to 0
	state = state * (1 - Trig1.kr(reset, 0.01));

	Out.kr(outBus, state);
}).add;

// ==========================================
// SYNTHDEF: COUNTER (trigger counter → gate)
// ==========================================
// mode 0: output gate every N triggers (modulo clock divider)
// mode 1: output gate after N triggers then stop (one-shot)
SynthDef(\daemon_counter, {
	|inBus=0, outBus=0, resetBus=0, count=8, mode=0|

	var trig, reset, pulses, gate, n;

	trig = In.kr(inBus, 1);
	reset = In.kr(resetBus, 1);

	n = count.clip(1, 256);
	pulses = PulseCount.kr(trig, reset);

	gate = Select.kr(mode.clip(0, 1), [
		// Mode 0: emit gate every N triggers (modulo divider)
		Trig1.kr((pulses % n) < 0.5 * trig, 0.001),
		// Mode 1: emit gate after exactly N triggers, then stop
		Trig1.kr((pulses > (n - 0.5)) * (pulses < (n + 0.5)) * trig, 0.001)
	]);

	Out.kr(outBus, gate);
}).add;

// ==========================================
// SYNTHDEF: CLOCK DIVIDER WITH RANDOM SKIP
// ==========================================
// Each trigger passes through with probability = density.
// Creates irregular rhythmic patterns from a regular clock.
SynthDef(\daemon_clock_divider_random, {
	|inBus=0, outBus=0, density=0.5|

	var trig, pass;

	trig = In.kr(inBus, 1);

	// Coin flip per trigger: pass or skip
	pass = TIRand.kr(0, 1000, trig) < (density.clip(0, 1) * 1000);

	Out.kr(outBus, trig * pass);
}).add;


// ==========================================
// LANGUAGE-SIDE: DAEMON_MACHINA (Full Turing Machine)
// ==========================================
// 16-bit shift register with probability-controlled feedback.
// At probability=1.0 the register loops perfectly.
// At probability=0.0 every new bit is a coin flip (maximum chaos).
// The length parameter constrains the effective loop window.
~DAEMON_MACHINA = { |bits=16, probability=0.5|
	(
		register: Array.fill(bits, { 2.rand }),
		bits: bits,
		probability: probability,
		length: bits,
		locked: false,

		tick: { |self|
			var msb = self[\register][0];
			// Shift left: rotate register by one position
			self[\register] = self[\register].rotate(-1);
			// New bit: probability determines if MSB is preserved or flipped
			if(self[\locked].not) {
				if(self[\probability].coin) {
					self[\register][self[\bits] - 1] = msb; // preserve = loop
				} {
					self[\register][self[\bits] - 1] = 1 - msb; // flip = mutate
				};
			};
		},

		cv: { |self|
			// Convert lower 8 bits to 0.0-1.0 CV value
			var val = 0;
			min(8, self[\bits]).do({ |i|
				val = val + (self[\register][i] * (2 ** i));
			});
			val / 255;
		},

		gate: { |self| self[\register][0] },

		setLength: { |self, len|
			self[\length] = len.clip(2, self[\bits]);
		},

		setProbability: { |self, prob|
			self[\probability] = prob.clip(0, 1);
		},

		lock: { |self| self[\locked] = true; },
		unlock: { |self| self[\locked] = false; },

		reset: { |self|
			self[\register] = Array.fill(self[\bits], { 2.rand });
		}
	);
};

// ==========================================
// LANGUAGE-SIDE: MOIRAI (Markov Chain with Training)
// ==========================================
// N-state Markov chain with temperature-controlled stochasticity.
// Can be trained on sequences to learn transition probabilities.
// Temperature < 1.0 sharpens distributions (more deterministic);
// temperature > 1.0 flattens them (more random).
~MOIRAI = { |numStates=8|
	(
		states: numStates,
		matrix: Array.fill(numStates, { Array.fill(numStates, { 1.0 / numStates }) }),
		values: Array.fill(numStates, { |i| i / (numStates - 1).max(1) }),
		current: 0,
		temperature: 0.5,
		history: List.new,

		next: { |self|
			var probs = self[\matrix][self[\current]].copy;
			// Temperature scaling: sharpen or flatten distribution
			probs = probs.pow(1 / self[\temperature].max(0.01));
			probs = probs / probs.sum.max(0.001);
			// Weighted random selection via cumulative sum
			var cumSum = 0, roll = 1.0.rand, chosen = 0;
			var found = false;
			probs.do({ |p, i|
				cumSum = cumSum + p;
				if(found.not and: { roll < cumSum }) {
					chosen = i;
					found = true;
				};
			});
			self[\history].add(self[\current]);
			if(self[\history].size > 256) { self[\history].removeAt(0) };
			self[\current] = chosen;
			self[\values][chosen];
		},

		train: { |self, seq|
			// Learn transition probabilities from an observed sequence
			var counts = Array.fill(self[\states], { Array.fill(self[\states], { 0 }) });
			(seq.size - 1).do({ |i|
				var from = seq[i].clip(0, self[\states] - 1);
				var to = seq[i+1].clip(0, self[\states] - 1);
				counts[from][to] = counts[from][to] + 1;
			});
			self[\states].do({ |from|
				var s = counts[from].sum.max(1);
				self[\matrix][from] = counts[from] / s;
			});
			"MOIRAI: Trained on % transitions".format(seq.size - 1).postln;
		},

		setTransition: { |self, from, to, weight|
			self[\matrix][from.clip(0, self[\states]-1)][to.clip(0, self[\states]-1)] = weight.max(0);
			// Renormalize the row
			var row = self[\matrix][from];
			var sum = row.sum.max(0.001);
			self[\matrix][from] = row / sum;
		},

		setTemperature: { |self, temp|
			self[\temperature] = temp.clip(0.01, 10.0);
		},

		reset: { |self|
			self[\current] = 0;
			self[\history] = List.new;
		}
	);
};

// ==========================================
// LANGUAGE-SIDE: GENESIS (Cellular Automata with Visualization)
// ==========================================
// 1D Wolfram cellular automaton. The rule number (0-255)
// defines the 8 neighborhood-to-output mappings.
// Supports center, random, and left seed patterns.
// Density output provides a single CV proportional to live cell count.
~GENESIS = { |width=32, rule=30|
	(
		cells: Array.fill(width, { 0 }),
		width: width,
		rule: rule,
		generation: 0,
		history: List.new,

		seed: { |self, type=\center|
			switch(type,
				\center, {
					self[\cells] = Array.fill(self[\width], { 0 });
					self[\cells][(self[\width] / 2).asInteger] = 1;
				},
				\random, {
					self[\cells] = Array.fill(self[\width], { 2.rand });
				},
				\left, {
					self[\cells] = Array.fill(self[\width], { 0 });
					self[\cells][0] = 1;
				}
			);
			self[\generation] = 0;
			self[\history] = List.new;
		},

		step: { |self|
			var next = Array.fill(self[\width], { 0 });
			self[\width].do({ |i|
				var l = self[\cells][(i - 1).wrap(0, self[\width] - 1)];
				var c = self[\cells][i];
				var r = self[\cells][(i + 1).wrap(0, self[\width] - 1)];
				var n = (l * 4) + (c * 2) + r; // neighborhood index 0-7
				next[i] = (self[\rule] >> n) & 1;
			});
			// Archive current generation for visualization
			self[\history].add(self[\cells].copy);
			if(self[\history].size > 128) { self[\history].removeAt(0) };
			self[\cells] = next;
			self[\generation] = self[\generation] + 1;
		},

		density: { |self|
			// Proportion of live cells: 0.0-1.0 CV
			self[\cells].sum / self[\width];
		},

		cv: { |self|
			// Convert first 8 cells to a normalized CV value
			var val = 0;
			min(8, self[\width]).do({ |i|
				val = val + (self[\cells][i] * (2 ** i));
			});
			val / 255;
		},

		getGates: { |self|
			self[\cells].copy;
		},

		setRule: { |self, r|
			self[\rule] = r.clip(0, 255).asInteger;
		},

		reset: { |self|
			self.seed(\center);
		}
	);
};

// ==========================================
// LANGUAGE-SIDE: SERPENS (Self-Patching Templates)
// ==========================================
// Pre-wired patch recipes that describe canonical generative topologies.
// Each template returns a list of module names and a description of
// how to connect them via the patch bay.
~SERPENS_TEMPLATES = (
	generativeLoop: { |clockBus, outBus|
		// Clock -> divider -> turing machine -> quantizer -> output
		"SERPENS: generativeLoop — clock -> divider -> turing -> quantizer -> osc".postln;
		// Returns suggested module chain and wiring description
		[
			[\horologium_divider, \daemon_turing, \grimoire_quantizer],
			"Connect clock outBus4 -> turing trigBus, turing outBusCV -> quantizer inBus"
		];
	},

	chaosModulation: {
		// Chaos oscillator -> slew limiter -> attenuverter -> target parameter
		"SERPENS: chaosModulation — chaos osc -> slew -> attenuverter -> target".postln;
		[
			[\athanor_chaos, \aqua_vitae_slew, \grimoire_attenuverter],
			"Connect chaos out -> slew in -> attenuverter in -> destination param bus"
		];
	},

	markovMelody: { |scaleName|
		// Markov chain -> quantizer -> voice -> output
		"SERPENS: markovMelody — markov -> quantizer -> voice".postln;
		[
			[\moirai, \grimoire_quantizer, \oscillator],
			"Use MOIRAI.next for CV, quantize to scale, send to oscillator freq bus"
		];
	},

	euclideanDrums: {
		// Multiple euclidean generators with different densities -> drum voices
		"SERPENS: euclideanDrums — parallel euclidean -> drum voices".postln;
		[
			[\daemon_euclidean_ext, \daemon_euclidean_ext, \daemon_euclidean_ext],
			"Create 3 instances with length=16, hits=4/7/11, route gates to drum synths"
		];
	},

	cellularTexture: {
		// Cellular automata rows -> individual oscillator frequencies
		"SERPENS: cellularTexture — CA rows -> oscillator bank".postln;
		[
			[\genesis, \grimoire_multiple, \oscillator_bank],
			"Step GENESIS each clock tick, map cell states to oscillator on/off gates"
		];
	}
);


// ==========================================
// OSC RESPONDERS: DAEMON (SynthDef instances)
// ==========================================
// Global daemon SynthDef instance registry
~DAEMON_SYNTH_INSTANCES = IdentityDictionary.new;

OSCdef(\daemon_create, { |msg|
	var type = msg[1].asSymbol;
	var name = msg[2].asSymbol;
	var synth;

	switch(type,
		\turing, {
			var trigBus = msg[3] ? 0;
			var bits = msg[4] ? 8;
			var prob = msg[5] ? 0.5;
			synth = Synth(\daemon_turing, [
				\trigBus, trigBus.asInteger,
				\bits, bits.asInteger,
				\probability, prob.asFloat
			]);
		},
		\bernoulli, {
			var inBus = msg[3] ? 0;
			var prob1 = msg[4] ? 0.5;
			var prob2 = msg[5] ? 0.5;
			var prob3 = msg[6] ? 0.5;
			synth = Synth(\daemon_bernoulli_cascade, [
				\inBus, inBus.asInteger,
				\prob1, prob1.asFloat,
				\prob2, prob2.asFloat,
				\prob3, prob3.asFloat
			]);
		},
		\flipflop, {
			var inBus = msg[3] ? 0;
			synth = Synth(\daemon_flipflop, [\inBus, inBus.asInteger]);
		},
		\counter, {
			var inBus = msg[3] ? 0;
			var count = msg[4] ? 8;
			var mode = msg[5] ? 0;
			synth = Synth(\daemon_counter, [
				\inBus, inBus.asInteger,
				\count, count.asInteger,
				\mode, mode.asInteger
			]);
		},
		\clockdiv, {
			var inBus = msg[3] ? 0;
			var density = msg[4] ? 0.5;
			synth = Synth(\daemon_clock_divider_random, [
				\inBus, inBus.asInteger,
				\density, density.asFloat
			]);
		}
	);

	if(synth.notNil) {
		~DAEMON_SYNTH_INSTANCES[name] = synth;
		"DAEMON: Created SynthDef '%' as '%'".format(type, name).postln;
	};
}, "/daemon/create");

OSCdef(\daemon_set, { |msg|
	// /daemon/set name param value
	var name = msg[1].asSymbol;
	var param = msg[2].asSymbol;
	var value = msg[3].asFloat;
	var synth = ~DAEMON_SYNTH_INSTANCES[name];
	if(synth.notNil) {
		synth.set(param, value);
	};
}, "/daemon/set");

OSCdef(\daemon_free, { |msg|
	var name = msg[1].asSymbol;
	var synth = ~DAEMON_SYNTH_INSTANCES[name];
	if(synth.notNil) {
		synth.free;
		~DAEMON_SYNTH_INSTANCES.removeAt(name);
		"DAEMON: Freed '%'".format(name).postln;
	};
}, "/daemon/free");

// ==========================================
// OSC RESPONDERS: DAEMON_MACHINA (Language-side Turing Machine)
// ==========================================
~DAEMON_MACHINA_INSTANCES = IdentityDictionary.new;

OSCdef(\machina_create, { |msg|
	var name = msg[1].asSymbol;
	var bits = (msg[2] ? 16).asInteger;
	var prob = (msg[3] ? 0.5).asFloat;
	~DAEMON_MACHINA_INSTANCES[name] = ~DAEMON_MACHINA.(bits, prob);
	"DAEMON_MACHINA: Created '%' (%bit, p=%)".format(name, bits, prob).postln;
}, "/daemon/machina/create");

OSCdef(\machina_tick, { |msg|
	var name = msg[1].asSymbol;
	var inst = ~DAEMON_MACHINA_INSTANCES[name];
	if(inst.notNil) { inst.tick };
}, "/daemon/machina/tick");

OSCdef(\machina_cv, { |msg|
	var name = msg[1].asSymbol;
	var outBusIdx = msg[2].asInteger;
	var inst = ~DAEMON_MACHINA_INSTANCES[name];
	if(inst.notNil) {
		var bus = Bus(\control, outBusIdx, 1, s);
		bus.set(inst.cv);
	};
}, "/daemon/machina/cv");

OSCdef(\machina_set, { |msg|
	var name = msg[1].asSymbol;
	var param = msg[2].asSymbol;
	var value = msg[3].asFloat;
	var inst = ~DAEMON_MACHINA_INSTANCES[name];
	if(inst.notNil) {
		switch(param,
			\probability, { inst.setProbability(value) },
			\length, { inst.setLength(value.asInteger) },
			\lock, { if(value > 0.5) { inst.lock } { inst.unlock } }
		);
	};
}, "/daemon/machina/set");

// ==========================================
// OSC RESPONDERS: MOIRAI (Markov Chain)
// ==========================================
~MOIRAI_INSTANCES = IdentityDictionary.new;

OSCdef(\moirai_create, { |msg|
	var name = msg[1].asSymbol;
	var states = (msg[2] ? 8).asInteger;
	~MOIRAI_INSTANCES[name] = ~MOIRAI.(states);
	"MOIRAI: Created '%' (% states)".format(name, states).postln;
}, "/moirai/create");

OSCdef(\moirai_next, { |msg|
	var name = msg[1].asSymbol;
	var outBusIdx = msg[2].asInteger;
	var inst = ~MOIRAI_INSTANCES[name];
	if(inst.notNil) {
		var val = inst.next;
		var bus = Bus(\control, outBusIdx, 1, s);
		bus.set(val);
	};
}, "/moirai/next");

OSCdef(\moirai_train, { |msg|
	// /moirai/train name val0 val1 val2 ...
	var name = msg[1].asSymbol;
	var seq = msg[2..].collect({ |v| v.asInteger });
	var inst = ~MOIRAI_INSTANCES[name];
	if(inst.notNil) { inst.train(seq) };
}, "/moirai/train");

OSCdef(\moirai_set, { |msg|
	var name = msg[1].asSymbol;
	var param = msg[2].asSymbol;
	var value = msg[3].asFloat;
	var inst = ~MOIRAI_INSTANCES[name];
	if(inst.notNil) {
		switch(param,
			\temperature, { inst.setTemperature(value) }
		);
	};
}, "/moirai/set");

// ==========================================
// OSC RESPONDERS: GENESIS (Cellular Automata)
// ==========================================
~GENESIS_INSTANCES = IdentityDictionary.new;

OSCdef(\genesis_create, { |msg|
	var name = msg[1].asSymbol;
	var width = (msg[2] ? 32).asInteger;
	var rule = (msg[3] ? 30).asInteger;
	var inst = ~GENESIS.(width, rule);
	inst.seed(\center);
	~GENESIS_INSTANCES[name] = inst;
	"GENESIS: Created '%' (width=%, rule=%)".format(name, width, rule).postln;
}, "/genesis/create");

OSCdef(\genesis_step, { |msg|
	var name = msg[1].asSymbol;
	var inst = ~GENESIS_INSTANCES[name];
	if(inst.notNil) { inst.step };
}, "/genesis/step");

OSCdef(\genesis_cv, { |msg|
	var name = msg[1].asSymbol;
	var outBusIdx = msg[2].asInteger;
	var inst = ~GENESIS_INSTANCES[name];
	if(inst.notNil) {
		var bus = Bus(\control, outBusIdx, 1, s);
		bus.set(inst.cv);
	};
}, "/genesis/cv");

OSCdef(\genesis_density, { |msg|
	var name = msg[1].asSymbol;
	var outBusIdx = msg[2].asInteger;
	var inst = ~GENESIS_INSTANCES[name];
	if(inst.notNil) {
		var bus = Bus(\control, outBusIdx, 1, s);
		bus.set(inst.density);
	};
}, "/genesis/density");

OSCdef(\genesis_set, { |msg|
	var name = msg[1].asSymbol;
	var param = msg[2].asSymbol;
	var value = msg[3];
	var inst = ~GENESIS_INSTANCES[name];
	if(inst.notNil) {
		switch(param,
			\rule, { inst.setRule(value.asInteger) },
			\seed, { inst.seed(value.asSymbol) }
		);
	};
}, "/genesis/set");

// ==========================================
// OSC RESPONDERS: SERPENS (Self-Patching Templates)
// ==========================================
OSCdef(\serpens_apply, { |msg|
	var template = msg[1].asSymbol;
	var fn = ~SERPENS_TEMPLATES[template];
	if(fn.notNil) {
		var result = fn.value;
		"SERPENS: Applied template '%'".format(template).postln;
		result[0].do({ |mod| "  Module: %".format(mod).postln });
		"  Wiring: %".format(result[1]).postln;
	} {
		"SERPENS: Unknown template '%'".format(template).postln;
	};
}, "/serpens/apply");

OSCdef(\serpens_list, { |msg|
	"SERPENS: Available templates:".postln;
	~SERPENS_TEMPLATES.keysValuesDo({ |key, val|
		"  - %".format(key).postln;
	});
}, "/serpens/list");

"--- BRAHMA: DAEMON Generative Suite Online (8 modules) ---".postln;
)
