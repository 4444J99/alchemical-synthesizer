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
	// ==========================================
	// MATERIALIZED SERPENS TEMPLATES
	// Each template creates real instances, allocates buses,
	// and starts generative processes. Returns cleanup function.
	// ==========================================

	generativeLoop: { |outBus|
		// Turing Machine → pentatonic quantization → Prima Materia
		var turing = ~DAEMON_MACHINA.(16, 0.7);
		var cvBus = Bus.control(s, 1);
		var gateBus = Bus.control(s, 1);
		var audioBus = Bus.audio(s, 2);
		var cleanup = List.new;
		var outTarget = outBus ? 0;
		"SERPENS: Materializing generativeLoop...".postln;

		// Store instance for clock bridge access
		~DAEMON_MACHINA_INSTANCES[\serpens_turing] = turing;

		// Register with clock bridge at 16th notes
		if(~DAEMON_CLOCK_BRIDGE.notNil) {
			~DAEMON_CLOCK_BRIDGE.register(\serpens_turing, \machina, turing, 1,
				cvBus.index, gateBus.index);
		};

		// Tdef: read CV bus, quantize to pentatonic, trigger Prima Materia
		Tdef(\serpens_gen_loop, {
			var pentatonic = [0, 2, 4, 7, 9]; // C D E G A
			var baseNote = 48;
			loop {
				var cv, gate, note, freq;
				cvBus.get({ |v| cv = v });
				gateBus.get({ |v| gate = v });
				cv = cv ? 0;
				gate = gate ? 0;

				if(gate > 0.5) {
					var voice;
					// Quantize CV to pentatonic
					note = baseNote + pentatonic.wrapAt((cv * 20).round.asInteger);
					freq = note.midicps;
					voice = Synth(\prima_materia, [
						\freq, freq, \velocity, 0.4, \gate, 1,
						\outBus, outTarget, \cutoff, cv.linexp(0, 1, 500, 6000),
						\atk, 0.01, \dec, 0.15, \sus, 0.3, \rel, 0.4,
						\osc1Type, 1, \osc2Level, 0.2
					], ~SC_GRP[\te], \addToTail);
					{ 0.12.wait; voice.set(\gate, 0); }.fork;
				};
				(60 / (~CHRONOS[\tempo] ? 120) / 4).wait;
			};
		}).play;

		cleanup.add({ Tdef(\serpens_gen_loop).stop });
		cleanup.add({ cvBus.free; gateBus.free; audioBus.free });
		cleanup.add({ ~DAEMON_MACHINA_INSTANCES.removeAt(\serpens_turing) });
		cleanup.add({
			if(~DAEMON_CLOCK_BRIDGE.notNil) {
				~DAEMON_CLOCK_BRIDGE.unregister(\serpens_turing);
			};
		});

		"SERPENS: generativeLoop ACTIVE (Turing → pentatonic → Prima Materia)".postln;
		[\generativeLoop, { cleanup.do({ |fn| fn.value }) }];
	},

	chaosModulation: { |targetParam, targetInstance|
		// Lorenz attractor → parameter modulation
		var lorenzX = Bus.control(s, 1);
		var lorenzY = Bus.control(s, 1);
		var lorenzZ = Bus.control(s, 1);
		var synth = Synth(\daemon_lorenz, [
			\outBusX, lorenzX.index, \outBusY, lorenzY.index, \outBusZ, lorenzZ.index,
			\sigma, 10, \rho, 28, \beta, 2.667, \rate, 1.5, \scale, 0.03
		]);
		~DAEMON_SYNTH_INSTANCES[\serpens_lorenz] = synth;
		"SERPENS: chaosModulation ACTIVE (Lorenz → 3 CV buses: %, %, %)".format(
			lorenzX.index, lorenzY.index, lorenzZ.index).postln;
		[\chaosModulation, {
			synth.free;
			lorenzX.free; lorenzY.free; lorenzZ.free;
			~DAEMON_SYNTH_INSTANCES.removeAt(\serpens_lorenz);
		}];
	},

	markovMelody: { |outBus|
		// MOIRAI Markov → melodic voice
		var markov = ~MOIRAI.(12);
		var pentatonic = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 12, 7];
		var outTarget = outBus ? 0;
		"SERPENS: Materializing markovMelody...".postln;
		markov.train(pentatonic);
		markov.setTemperature(0.6);
		~MOIRAI_INSTANCES[\serpens_markov] = markov;

		Tdef(\serpens_markov_melody, {
			var baseNote = 52;
			loop {
				var interval = (markov.next * 24).round.asInteger;
				var note = (baseNote + interval).clip(36, 84);
				var voice = Synth(\prima_materia, [
					\freq, note.midicps, \velocity, 0.35, \gate, 1,
					\outBus, outTarget, \cutoff, 3000,
					\atk, 0.02, \dec, 0.2, \sus, 0.5, \rel, 0.6,
					\osc1Type, 0, \osc2Type, 1, \osc2Level, 0.3, \osc2Detune, 3
				], ~SC_GRP[\te], \addToTail);
				{ 0.2.wait; voice.set(\gate, 0); }.fork;
				(60 / (~CHRONOS[\tempo] ? 120) / 4).wait;
			};
		}).play;

		"SERPENS: markovMelody ACTIVE (MOIRAI → pentatonic → Prima Materia)".postln;
		[\markovMelody, {
			Tdef(\serpens_markov_melody).stop;
			~MOIRAI_INSTANCES.removeAt(\serpens_markov);
		}];
	},

	euclideanDrums: { |outBus|
		// 3 Euclidean generators → Golem drum voices
		var kick = ~DAEMON_EUCLIDEAN_EXT.(16, 4, 2, 0);
		var hat = ~DAEMON_EUCLIDEAN_EXT.(16, 7, 3, 0);
		var snare = ~DAEMON_EUCLIDEAN_EXT.(16, 3, 1, 4);
		var outTarget = outBus ? 0;
		"SERPENS: Materializing euclideanDrums...".postln;
		kick.generate; hat.generate; snare.generate;

		~DAEMON_SEQ_INSTANCES[\serpens_kick] = [\euclidean, kick];
		~DAEMON_SEQ_INSTANCES[\serpens_hat] = [\euclidean, hat];
		~DAEMON_SEQ_INSTANCES[\serpens_snare] = [\euclidean, snare];

		// Register with clock bridge
		if(~DAEMON_CLOCK_BRIDGE.notNil) {
			~DAEMON_CLOCK_BRIDGE.register(\serpens_kick, \euclidean, kick, 1, nil, nil);
			~DAEMON_CLOCK_BRIDGE.register(\serpens_hat, \euclidean, hat, 1, nil, nil);
			~DAEMON_CLOCK_BRIDGE.register(\serpens_snare, \euclidean, snare, 1, nil, nil);
		};

		Tdef(\serpens_euclid_drums, {
			loop {
				kick.advance; hat.advance; snare.advance;
				if(kick.gate > 0) {
					Synth(\drum_subtractive, [
						\outBus, outTarget, \freq, 55, \velocity, kick.velocity * 0.6,
						\gate, 1, \cutoff, 800, \envAmt, 0.8
					], ~SC_GRP[\te], \addToTail);
				};
				if(hat.gate > 0) {
					Synth(\drum_noise, [
						\outBus, outTarget, \freq, 8000, \velocity, hat.velocity * 0.3,
						\gate, 1, \decay, 0.05
					], ~SC_GRP[\te], \addToTail);
				};
				if(snare.gate > 0) {
					Synth(\drum_fm, [
						\outBus, outTarget, \freq, 200, \velocity, snare.velocity * 0.4,
						\gate, 1, \modRatio, 2.3, \modIndex, 3
					], ~SC_GRP[\te], \addToTail);
				};
				(60 / (~CHRONOS[\tempo] ? 120) / 4).wait;
			};
		}).play;

		"SERPENS: euclideanDrums ACTIVE (E(4,16) kick + E(7,16) hat + E(3,16) snare)".postln;
		[\euclideanDrums, {
			Tdef(\serpens_euclid_drums).stop;
			[\serpens_kick, \serpens_hat, \serpens_snare].do({ |k|
				~DAEMON_SEQ_INSTANCES.removeAt(k);
				if(~DAEMON_CLOCK_BRIDGE.notNil) { ~DAEMON_CLOCK_BRIDGE.unregister(k) };
			});
		}];
	},

	cellularTexture: { |outBus|
		// Cellular automata → oscillator bank
		var ca = ~GENESIS.(16, 30);
		var outTarget = outBus ? 0;
		var baseFreq = 220;
		"SERPENS: Materializing cellularTexture...".postln;
		ca.seed(\random);
		~GENESIS_INSTANCES[\serpens_ca] = ca;

		Tdef(\serpens_cellular, {
			loop {
				var cells;
				ca.step;
				cells = ca.getGates;
				// Map active cells to sine tones at harmonic intervals
				cells.do({ |active, i|
					if(active > 0) {
						var freq = baseFreq * (i + 1) * 0.5;
						if(freq < 4000) {
							var grain = Synth(\prima_materia, [
								\freq, freq, \velocity, 0.08, \gate, 1,
								\outBus, outTarget, \osc1Type, 0,
								\atk, 0.02, \dec, 0.1, \sus, 0.0, \rel, 0.15,
								\cutoff, 5000
							], ~SC_GRP[\te], \addToTail);
							{ 0.08.wait; grain.set(\gate, 0); }.fork;
						};
					};
				});
				(60 / (~CHRONOS[\tempo] ? 120) / 2).wait; // 8th notes
			};
		}).play;

		"SERPENS: cellularTexture ACTIVE (Rule 30 → harmonic oscillator bank)".postln;
		[\cellularTexture, {
			Tdef(\serpens_cellular).stop;
			~GENESIS_INSTANCES.removeAt(\serpens_ca);
		}];
	}
);

// Active SERPENS instances (for cleanup)
~SERPENS_ACTIVE = IdentityDictionary.new;


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
	var outBus = if(msg.size > 2) { msg[2].asInteger } { 0 };
	var fn = ~SERPENS_TEMPLATES[template];
	if(fn.notNil) {
		var result;
		// Stop existing instance of same template if running
		if(~SERPENS_ACTIVE[template].notNil) {
			~SERPENS_ACTIVE[template].value; // call cleanup
			~SERPENS_ACTIVE.removeAt(template);
		};
		result = fn.value(outBus);
		~SERPENS_ACTIVE[result[0].asSymbol] = result[1]; // store cleanup fn
		// Broadcast state to web
		if(~VISUAL_CORTEX.notNil) {
			~VISUAL_CORTEX.target.sendMsg("/serpens/state", template.asString, 1);
		};
	} {
		"SERPENS: Unknown template '%'".format(template).postln;
	};
}, "/serpens/apply");

OSCdef(\serpens_list, { |msg|
	"SERPENS: Available templates:".postln;
	~SERPENS_TEMPLATES.keysValuesDo({ |key, val|
		var active = ~SERPENS_ACTIVE[key].notNil;
		"  - % %".format(key, if(active, "[ACTIVE]", "")).postln;
	});
	// Broadcast template list to web
	if(~VISUAL_CORTEX.notNil) {
		~SERPENS_TEMPLATES.keysValuesDo({ |key, val|
			var active = ~SERPENS_ACTIVE[key].notNil;
			~VISUAL_CORTEX.target.sendMsg("/serpens/template",
				key.asString, active.asInteger);
		});
		~VISUAL_CORTEX.target.sendMsg("/serpens/list/done",
			~SERPENS_TEMPLATES.size);
	};
}, "/serpens/list");

OSCdef(\serpens_stop, { |msg|
	var template = msg[1].asSymbol;
	if(~SERPENS_ACTIVE[template].notNil) {
		~SERPENS_ACTIVE[template].value; // call cleanup
		~SERPENS_ACTIVE.removeAt(template);
		"SERPENS: Stopped template '%'".format(template).postln;
		if(~VISUAL_CORTEX.notNil) {
			~VISUAL_CORTEX.target.sendMsg("/serpens/state", template.asString, 0);
		};
	} {
		"SERPENS: Template '%' not active".format(template).postln;
	};
}, "/serpens/stop");

OSCdef(\serpens_stop_all, {
	~SERPENS_ACTIVE.keysValuesDo({ |key, cleanup|
		cleanup.value;
		"SERPENS: Stopped '%'".format(key).postln;
	});
	~SERPENS_ACTIVE = IdentityDictionary.new;
	"SERPENS: All templates stopped".postln;
}, "/serpens/stopAll");

// ==========================================
// SYNTHDEF: LORENZ ATTRACTOR (3-axis chaotic CV)
// ==========================================
// Continuous Lorenz system producing 3 correlated chaotic CV outputs.
// sigma, rho, beta control the attractor topology.
// Classic chaotic regime: sigma=10, rho=28, beta=2.667
// Rate controls the speed of evolution.
SynthDef(\daemon_lorenz, {
    |outBusX=0, outBusY=1, outBusZ=2,
     sigma=10, rho=28, beta=2.667,
     rate=1.0, scale=0.02|

    var x, y, z, dt;
    var fb = LocalIn.kr(3);

    x = fb[0];
    y = fb[1];
    z = fb[2];

    dt = rate.clip(0.01, 10) * ControlDur.ir;

    // Lorenz differential equations
    // dx/dt = sigma * (y - x)
    // dy/dt = x * (rho - z) - y
    // dz/dt = x * y - beta * z
    x = x + (sigma.clip(0.1, 50) * (y - x) * dt);
    y = y + ((fb[0] * (rho.clip(0.1, 100) - z) - y) * dt);
    z = z + ((fb[0] * fb[1] - beta.clip(0.1, 20) * z) * dt);

    // Prevent NaN/inf with soft clipping
    x = x.clip(-100, 100);
    y = y.clip(-100, 100);
    z = z.clip(-100, 100);

    // Seed with small random values if system collapses to zero
    x = Select.kr((x.abs + y.abs + z.abs) < 0.001, [x, Rand(0.1, 1.0)]);

    LocalOut.kr([x, y, z]);

    // Scale to 0-1 CV range (Lorenz typically spans ~-30 to +30)
    Out.kr(outBusX, (x * scale.clip(0.001, 1)).clip(-1, 1).linlin(-1, 1, 0, 1));
    Out.kr(outBusY, (y * scale.clip(0.001, 1)).clip(-1, 1).linlin(-1, 1, 0, 1));
    Out.kr(outBusZ, (z * scale.clip(0.001, 1)).clip(-1, 1).linlin(-1, 1, 0, 1));
}).add;

// ==========================================
// SYNTHDEF: HENON MAP (2-axis chaotic CV)
// ==========================================
// Discrete Henon map producing 2 correlated chaotic CV outputs.
// Classic chaotic regime: a=1.4, b=0.3
// Each trigger advances the map one step.
SynthDef(\daemon_henon, {
    |outBusX=0, outBusY=1, trigBus=0,
     a=1.4, b=0.3|

    var trig, x, y, newX, newY;
    var fb = LocalIn.kr(2);

    trig = In.kr(trigBus, 1);

    x = fb[0];
    y = fb[1];

    // Henon map equations:
    // x_{n+1} = 1 - a * x_n^2 + y_n
    // y_{n+1} = b * x_n
    newX = 1 - (a.clip(0.1, 2.0) * x.squared) + y;
    newY = b.clip(0.01, 1.0) * x;

    // Latch: only advance on trigger
    newX = Latch.kr(newX.clip(-2, 2), trig);
    newY = Latch.kr(newY.clip(-2, 2), trig);

    // Seed with small random value if collapsed
    newX = Select.kr((newX.abs + newY.abs) < 0.0001, [newX, Rand(0.1, 0.5)]);

    LocalOut.kr([newX, newY]);

    // Scale to 0-1 CV range (Henon typically spans ~-1.5 to +1.5)
    Out.kr(outBusX, newX.linlin(-1.5, 1.5, 0, 1).clip(0, 1));
    Out.kr(outBusY, newY.linlin(-0.5, 0.5, 0, 1).clip(0, 1));
}).add;

// ==========================================
// SYNTHDEF: ROSSLER ATTRACTOR (3-axis chaotic CV)
// ==========================================
// Continuous Rössler system: slower, more regular than Lorenz.
// Produces quasi-periodic orbits that transition to chaos.
// a, b, c control the topology. Classic: a=0.2, b=0.2, c=5.7
SynthDef(\daemon_rossler, {
    |outBusX=0, outBusY=1, outBusZ=2,
     a=0.2, b=0.2, c=5.7,
     rate=1.0, scale=0.05|

    var x, y, z, dt;
    var fb = LocalIn.kr(3);

    x = fb[0];
    y = fb[1];
    z = fb[2];

    dt = rate.clip(0.01, 10) * ControlDur.ir;

    // Rössler differential equations
    // dx/dt = -y - z
    // dy/dt = x + a*y
    // dz/dt = b + z*(x - c)
    x = x + ((-1 * y - z) * dt);
    y = y + ((fb[0] + (a.clip(0.01, 1) * y)) * dt);
    z = z + ((b.clip(0.01, 2) + (z * (fb[0] - c.clip(0.1, 20)))) * dt);

    // Prevent NaN/inf
    x = x.clip(-100, 100);
    y = y.clip(-100, 100);
    z = z.clip(-100, 100);

    // Seed if collapsed
    x = Select.kr((x.abs + y.abs + z.abs) < 0.001, [x, Rand(0.1, 1.0)]);

    LocalOut.kr([x, y, z]);

    // Scale to 0-1 CV range
    Out.kr(outBusX, (x * scale.clip(0.001, 1)).clip(-1, 1).linlin(-1, 1, 0, 1));
    Out.kr(outBusY, (y * scale.clip(0.001, 1)).clip(-1, 1).linlin(-1, 1, 0, 1));
    Out.kr(outBusZ, (z * scale.clip(0.001, 1)).clip(-1, 1).linlin(-1, 1, 0, 1));
}).add;

// OSC responders for chaos attractors
OSCdef(\daemon_lorenz_create, { |msg|
    var name = msg[1].asSymbol;
    var sigma = (msg[2] ? 10).asFloat;
    var rho = (msg[3] ? 28).asFloat;
    var beta = (msg[4] ? 2.667).asFloat;
    var synth = Synth(\daemon_lorenz, [
        \sigma, sigma, \rho, rho, \beta, beta
    ]);
    ~DAEMON_SYNTH_INSTANCES[name] = synth;
    "DAEMON: Lorenz attractor '%' created".format(name).postln;
}, "/daemon/lorenz/create");

OSCdef(\daemon_henon_create, { |msg|
    var name = msg[1].asSymbol;
    var a = (msg[2] ? 1.4).asFloat;
    var b = (msg[3] ? 0.3).asFloat;
    var synth = Synth(\daemon_henon, [\a, a, \b, b]);
    ~DAEMON_SYNTH_INSTANCES[name] = synth;
    "DAEMON: Henon map '%' created".format(name).postln;
}, "/daemon/henon/create");

OSCdef(\daemon_rossler_create, { |msg|
    var name = msg[1].asSymbol;
    var a = (msg[2] ? 0.2).asFloat;
    var b = (msg[3] ? 0.2).asFloat;
    var c = (msg[4] ? 5.7).asFloat;
    var synth = Synth(\daemon_rossler, [\a, a, \b, b, \c, c]);
    ~DAEMON_SYNTH_INSTANCES[name] = synth;
    "DAEMON: Rossler attractor '%' created".format(name).postln;
}, "/daemon/rossler/create");

"--- BRAHMA: DAEMON Generative Suite Online (11 modules) ---".postln;

// --- PATCH BAY REGISTRATION: Generative Modules ---
if(~PATCH_BAY.notNil) {
    // SynthDef-based generative modules (destinations for parameter modulation)
    [
        [\daemon_turing, [
            [\probability, "mutation probability"],
            [\bits, "sequence bit length"]
        ]],
        [\daemon_bernoulli_cascade, [
            [\prob1, "branch 1 probability"],
            [\prob2, "branch 2 probability"],
            [\prob3, "branch 3 probability"]
        ]],
        [\daemon_clock_divider_random, [
            [\density, "division density"]
        ]],
        [\daemon_prob_gate, [
            [\probability, "gate probability"],
            [\mode, "gate mode"]
        ]],
        [\daemon_lorenz, [
            [\sigma, "Lorenz sigma"],
            [\rho, "Lorenz rho"],
            [\beta, "Lorenz beta"],
            [\rate, "evolution rate"],
            [\scale, "output scale"]
        ]],
        [\daemon_henon, [
            [\a, "Henon a param"],
            [\b, "Henon b param"]
        ]],
        [\daemon_rossler, [
            [\a, "Rossler a param"],
            [\b, "Rossler b param"],
            [\c, "Rossler c param"],
            [\rate, "evolution rate"],
            [\scale, "output scale"]
        ]]
    ].do({ |moduleSpec|
        var synthName = moduleSpec[0];
        var params = moduleSpec[1];
        params.do({ |p|
            ~PATCH_BAY.registerDestination(
                (synthName.asString ++ "_" ++ p[0].asString).asSymbol,
                p[0], synthName.asString ++ " " ++ p[1]
            );
        });
    });
    "  -> Generative modules registered with Patch Bay".postln;
};

// --- MODULE REGISTRY REGISTRATION ---
if(~MODULE_REGISTRY.notNil) {
    // SynthDef: Turing Machine (audio-rate shift register CV/gate)
    ~MODULE_REGISTRY.register(\daemon_turing, \daemon, \daemon_turing, [
        (\name: \outBusCV, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "CV output bus index"),
        (\name: \outBusGate, \default: 1, \min: 0, \max: 4095, \units: "", \desc: "Gate output bus index"),
        (\name: \trigBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Trigger input bus index"),
        (\name: \bits, \default: 8, \min: 1, \max: 16, \units: "", \desc: "Register bit depth"),
        (\name: \probability, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Flip probability"),
    ], ~SC_GRP[\te], "Audio-rate shift register CV/gate generator");

    // SynthDef: Bernoulli Cascade (3-level probability routing tree)
    ~MODULE_REGISTRY.register(\daemon_bernoulli_cascade, \daemon, \daemon_bernoulli_cascade, [
        (\name: \inBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Trigger input bus"),
        (\name: \outBus1, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Output bus 1"),
        (\name: \outBus2, \default: 1, \min: 0, \max: 4095, \units: "", \desc: "Output bus 2"),
        (\name: \outBus3, \default: 2, \min: 0, \max: 4095, \units: "", \desc: "Output bus 3"),
        (\name: \outBus4, \default: 3, \min: 0, \max: 4095, \units: "", \desc: "Output bus 4"),
        (\name: \prob1, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Level 1 branch probability"),
        (\name: \prob2, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Level 2 branch A probability"),
        (\name: \prob3, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Level 3 branch B probability"),
    ], ~SC_GRP[\te], "3-level probability routing tree for trigger distribution");

    // SynthDef: Flip-Flop (toggle on trigger)
    ~MODULE_REGISTRY.register(\daemon_flipflop, \daemon, \daemon_flipflop, [
        (\name: \inBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Trigger input bus"),
        (\name: \outBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Toggle output bus"),
        (\name: \resetBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Reset input bus"),
    ], ~SC_GRP[\te], "Toggle between 0 and 1 on each trigger with reset");

    // SynthDef: Counter (trigger counter with modulo/one-shot modes)
    ~MODULE_REGISTRY.register(\daemon_counter, \daemon, \daemon_counter, [
        (\name: \inBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Trigger input bus"),
        (\name: \outBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Gate output bus"),
        (\name: \resetBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Reset input bus"),
        (\name: \count, \default: 8, \min: 1, \max: 256, \units: "", \desc: "Trigger count threshold"),
        (\name: \mode, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Mode: 0=modulo divider, 1=one-shot"),
    ], ~SC_GRP[\te], "Trigger counter with modulo clock divider and one-shot modes");

    // SynthDef: Clock Divider Random (stochastic trigger thinning)
    ~MODULE_REGISTRY.register(\daemon_clock_divider_random, \daemon, \daemon_clock_divider_random, [
        (\name: \inBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Clock input bus"),
        (\name: \outBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Thinned clock output bus"),
        (\name: \density, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Pass-through probability"),
    ], ~SC_GRP[\te], "Stochastic clock divider — each trigger passes with probability density");

    // SynthDef: Lorenz Attractor (3-axis chaotic CV)
    ~MODULE_REGISTRY.register(\daemon_lorenz, \daemon, \daemon_lorenz, [
        (\name: \outBusX, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "X-axis CV output bus"),
        (\name: \outBusY, \default: 1, \min: 0, \max: 4095, \units: "", \desc: "Y-axis CV output bus"),
        (\name: \outBusZ, \default: 2, \min: 0, \max: 4095, \units: "", \desc: "Z-axis CV output bus"),
        (\name: \sigma, \default: 10, \min: 0.1, \max: 50, \units: "", \desc: "Lorenz sigma parameter"),
        (\name: \rho, \default: 28, \min: 0.1, \max: 100, \units: "", \desc: "Lorenz rho parameter"),
        (\name: \beta, \default: 2.667, \min: 0.1, \max: 20, \units: "", \desc: "Lorenz beta parameter"),
        (\name: \rate, \default: 1.0, \min: 0.01, \max: 10, \units: "", \desc: "Evolution rate"),
        (\name: \scale, \default: 0.02, \min: 0.001, \max: 1, \units: "", \desc: "Output scale factor"),
    ], ~SC_GRP[\te], "Continuous Lorenz attractor producing 3 correlated chaotic CV outputs");

    // SynthDef: Henon Map (2-axis chaotic CV)
    ~MODULE_REGISTRY.register(\daemon_henon, \daemon, \daemon_henon, [
        (\name: \outBusX, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "X-axis CV output bus"),
        (\name: \outBusY, \default: 1, \min: 0, \max: 4095, \units: "", \desc: "Y-axis CV output bus"),
        (\name: \trigBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Trigger input bus"),
        (\name: \a, \default: 1.4, \min: 0.1, \max: 2.0, \units: "", \desc: "Henon a parameter"),
        (\name: \b, \default: 0.3, \min: 0.01, \max: 1.0, \units: "", \desc: "Henon b parameter"),
    ], ~SC_GRP[\te], "Discrete Henon map producing 2 correlated chaotic CV outputs");

    // SynthDef: Rossler Attractor (3-axis chaotic CV)
    ~MODULE_REGISTRY.register(\daemon_rossler, \daemon, \daemon_rossler, [
        (\name: \outBusX, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "X-axis CV output bus"),
        (\name: \outBusY, \default: 1, \min: 0, \max: 4095, \units: "", \desc: "Y-axis CV output bus"),
        (\name: \outBusZ, \default: 2, \min: 0, \max: 4095, \units: "", \desc: "Z-axis CV output bus"),
        (\name: \a, \default: 0.2, \min: 0.01, \max: 1, \units: "", \desc: "Rossler a parameter"),
        (\name: \b, \default: 0.2, \min: 0.01, \max: 2, \units: "", \desc: "Rossler b parameter"),
        (\name: \c, \default: 5.7, \min: 0.1, \max: 20, \units: "", \desc: "Rossler c parameter"),
        (\name: \rate, \default: 1.0, \min: 0.01, \max: 10, \units: "", \desc: "Evolution rate"),
        (\name: \scale, \default: 0.05, \min: 0.001, \max: 1, \units: "", \desc: "Output scale factor"),
    ], ~SC_GRP[\te], "Continuous Rossler attractor producing quasi-periodic to chaotic CV");

    // Language-side: DAEMON_MACHINA (full Turing Machine)
    ~MODULE_REGISTRY.register(\DAEMON_MACHINA, \daemon, \DAEMON_MACHINA, [
        (\name: \bits, \default: 16, \min: 1, \max: 32, \units: "", \desc: "Shift register bit depth"),
        (\name: \probability, \default: 0.5, \min: 0, \max: 1, \units: "", \desc: "Bit preservation probability"),
        (\name: \length, \default: 16, \min: 2, \max: 32, \units: "", \desc: "Effective loop window length"),
        (\name: \locked, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Lock register (1=frozen)"),
    ], ~SC_GRP[\te], "Language-side 16-bit shift register with probability-controlled feedback");

    // Language-side: MOIRAI (Markov chain with training)
    ~MODULE_REGISTRY.register(\MOIRAI, \daemon, \MOIRAI, [
        (\name: \numStates, \default: 8, \min: 2, \max: 64, \units: "", \desc: "Number of Markov states"),
        (\name: \temperature, \default: 0.5, \min: 0.01, \max: 10.0, \units: "", \desc: "Stochasticity temperature"),
    ], ~SC_GRP[\te], "N-state Markov chain with trainable transition probabilities");

    // Language-side: GENESIS (cellular automata)
    ~MODULE_REGISTRY.register(\GENESIS, \daemon, \GENESIS, [
        (\name: \width, \default: 32, \min: 4, \max: 256, \units: "cells", \desc: "Automaton width"),
        (\name: \rule, \default: 30, \min: 0, \max: 255, \units: "", \desc: "Wolfram rule number (0-255)"),
    ], ~SC_GRP[\te], "1D Wolfram cellular automaton with density and CV outputs");

    // SERPENS Templates (self-patching recipes)
    ~MODULE_REGISTRY.register(\SERPENS_generativeLoop, \daemon, \SERPENS_generativeLoop, [
        (\name: \outBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Audio output bus"),
    ], ~SC_GRP[\te], "SERPENS: Turing Machine -> pentatonic quantization -> Prima Materia");

    ~MODULE_REGISTRY.register(\SERPENS_chaosModulation, \daemon, \SERPENS_chaosModulation, [
        (\name: \targetParam, \default: 0, \min: 0, \max: 1, \units: "", \desc: "Target parameter to modulate"),
    ], ~SC_GRP[\te], "SERPENS: Lorenz attractor -> 3-axis parameter modulation");

    ~MODULE_REGISTRY.register(\SERPENS_markovMelody, \daemon, \SERPENS_markovMelody, [
        (\name: \outBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Audio output bus"),
    ], ~SC_GRP[\te], "SERPENS: MOIRAI Markov chain -> melodic voice");

    ~MODULE_REGISTRY.register(\SERPENS_euclideanDrums, \daemon, \SERPENS_euclideanDrums, [
        (\name: \outBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Audio output bus"),
    ], ~SC_GRP[\te], "SERPENS: 3 Euclidean generators -> Golem drum voices");

    ~MODULE_REGISTRY.register(\SERPENS_cellularTexture, \daemon, \SERPENS_cellularTexture, [
        (\name: \outBus, \default: 0, \min: 0, \max: 4095, \units: "", \desc: "Audio output bus"),
    ], ~SC_GRP[\te], "SERPENS: Cellular automata -> harmonic oscillator bank texture");

    "  -> DAEMON generative modules registered with Module Registry".postln;
};
)
