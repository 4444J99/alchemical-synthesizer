/*
  Phase 5: SIBYL — Modular Sequencers
  Step Sequencer, Euclidean Generator, Shift Register (Turing Machine),
  Markov Chain, Cellular Automata, L-System, Bernoulli Gate, Comparator Sequencer
*/

(
// ==========================================
// STEP SEQUENCER (1-64 steps, multiple directions)
// ==========================================
~SIBYL_STEP = { |numSteps=16, direction=0|
    // direction: 0=forward, 1=backward, 2=pendulum, 3=random
    var seq = (
        steps: Array.fill(numSteps, { 0.5 }),
        gates: Array.fill(numSteps, { true }),
        pos: 0,
        numSteps: numSteps,
        direction: direction,
        pendulumForward: true,

        advance: { |self|
            switch(self[\direction],
                0, { // Forward
                    self[\pos] = (self[\pos] + 1) % self[\numSteps];
                },
                1, { // Backward
                    self[\pos] = (self[\pos] - 1).wrap(0, self[\numSteps] - 1);
                },
                2, { // Pendulum
                    if(self[\pendulumForward]) {
                        self[\pos] = self[\pos] + 1;
                        if(self[\pos] >= (self[\numSteps] - 1)) {
                            self[\pendulumForward] = false;
                        };
                    } {
                        self[\pos] = self[\pos] - 1;
                        if(self[\pos] <= 0) {
                            self[\pendulumForward] = true;
                        };
                    };
                },
                3, { // Random
                    self[\pos] = self[\numSteps].rand;
                }
            );
        },

        getValue: { |self|
            self[\steps][self[\pos]];
        },

        getGate: { |self|
            self[\gates][self[\pos]].asInteger;
        },

        setStep: { |self, idx, val|
            if(idx < self[\numSteps]) {
                self[\steps][idx] = val.clip(0, 1);
            };
        },

        setGate: { |self, idx, val|
            if(idx < self[\numSteps]) {
                self[\gates][idx] = val.asBoolean;
            };
        },

        reset: { |self|
            self[\pos] = 0;
            self[\pendulumForward] = true;
        }
    );
    seq;
};

// ==========================================
// EUCLIDEAN GENERATOR
// ==========================================
~SIBYL_EUCLIDEAN = { |length=16, fills=4, rotation=0|
    var seq = (
        length: length,
        fills: fills,
        rotation: rotation,
        pattern: nil,
        pos: 0,

        generate: { |self|
            var pat = Array.fill(self[\length], { false });
            var bucket = 0;
            self[\fills].clip(0, self[\length]).do({ |i|
                bucket = bucket + self[\fills];
                if(bucket >= self[\length]) {
                    bucket = bucket - self[\length];
                    pat[(i + self[\rotation]) % self[\length]] = true;
                };
            });
            // Bresenham
            pat = Array.fill(self[\length], { |i|
                ((i * self[\fills]) % self[\length]) < self[\fills];
            });
            // Apply rotation
            pat = pat.rotate(self[\rotation].asInteger);
            self[\pattern] = pat;
        },

        advance: { |self|
            if(self[\pattern].isNil) { self.generate };
            self[\pos] = (self[\pos] + 1) % self[\length];
        },

        getGate: { |self|
            if(self[\pattern].isNil) { self.generate };
            self[\pattern][self[\pos]].asInteger;
        },

        setParams: { |self, length, fills, rotation|
            self[\length] = length.clip(1, 64);
            self[\fills] = fills.clip(0, self[\length]);
            self[\rotation] = rotation.clip(0, self[\length] - 1);
            self.generate;
        },

        reset: { |self|
            self[\pos] = 0;
        }
    );
    seq.generate;
    seq;
};

// ==========================================
// SHIFT REGISTER / TURING MACHINE
// ==========================================
~SIBYL_TURING = { |bits=8, probability=0.5|
    var seq = (
        register: Array.fill(bits, { 2.rand }),
        bits: bits,
        probability: probability,
        locked: false,

        advance: { |self|
            if(self[\locked].not) {
                // Shift register left, new bit based on probability
                var newBit;
                if(self[\probability].coin) {
                    newBit = self[\register].last;  // Keep (loop)
                } {
                    newBit = 2.rand;  // Flip (random)
                };
                self[\register] = self[\register].rotate(-1);
                self[\register][self[\bits] - 1] = newBit;
            } {
                // Locked: just rotate
                self[\register] = self[\register].rotate(-1);
            };
        },

        getValue: { |self|
            // Convert lower 8 bits to 0-1 CV
            var val = 0;
            min(8, self[\bits]).do({ |i|
                val = val + (self[\register][i] * (2 ** i));
            });
            val / 255;
        },

        getGate: { |self|
            self[\register][0];
        },

        setProbability: { |self, prob|
            self[\probability] = prob.clip(0, 1);
        },

        lock: { |self|
            self[\locked] = true;
        },

        unlock: { |self|
            self[\locked] = false;
        }
    );
    seq;
};

// ==========================================
// MARKOV CHAIN
// ==========================================
~SIBYL_MARKOV = { |numStates=8, temperature=0.5|
    var seq = (
        numStates: numStates,
        // Transition matrix: probabilities[from][to]
        matrix: Array.fill(numStates, { Array.fill(numStates, { 1.0 / numStates }) }),
        values: Array.fill(numStates, { |i| i / (numStates - 1).max(1) }),
        currentState: 0,
        temperature: temperature,
        history: List.new,

        advance: { |self|
            var probs = self[\matrix][self[\currentState]].copy;
            // Apply temperature
            if(self[\temperature] < 1.0) {
                probs = probs.pow(1 / self[\temperature].max(0.01));
                probs = probs / probs.sum.max(0.001);
            };
            // Weighted random selection
            var cumSum = 0;
            var roll = 1.0.rand;
            var nextState = self[\numStates] - 1;
            probs.do({ |p, i|
                cumSum = cumSum + p;
                if(roll < cumSum and: { nextState == (self[\numStates] - 1) }) {
                    nextState = i;
                };
            });
            self[\history].add(self[\currentState]);
            if(self[\history].size > 256) { self[\history].removeAt(0) };
            self[\currentState] = nextState;
        },

        getValue: { |self|
            self[\values][self[\currentState]];
        },

        setTransition: { |self, from, to, weight|
            self[\matrix][from][to] = weight.max(0);
            // Renormalize row
            var row = self[\matrix][from];
            var sum = row.sum.max(0.001);
            self[\matrix][from] = row / sum;
        },

        train: { |self, sequence|
            // Learn transition probabilities from a sequence
            var counts = Array.fill(self[\numStates], {
                Array.fill(self[\numStates], { 0 });
            });
            (sequence.size - 1).do({ |i|
                var from = sequence[i].clip(0, self[\numStates] - 1);
                var to = sequence[i+1].clip(0, self[\numStates] - 1);
                counts[from][to] = counts[from][to] + 1;
            });
            self[\numStates].do({ |from|
                var rowSum = counts[from].sum.max(1);
                self[\matrix][from] = counts[from] / rowSum;
            });
        },

        reset: { |self|
            self[\currentState] = 0;
            self[\history] = List.new;
        }
    );
    seq;
};

// ==========================================
// CELLULAR AUTOMATA (1D Wolfram rules)
// ==========================================
~SIBYL_AUTOMATA = { |numCells=16, rule=30|
    var seq = (
        cells: Array.fill(numCells, { 2.rand }),
        numCells: numCells,
        rule: rule,
        generation: 0,

        advance: { |self|
            var newCells = Array.fill(self[\numCells], { 0 });
            self[\numCells].do({ |i|
                var left = self[\cells][(i - 1).wrap(0, self[\numCells] - 1)];
                var center = self[\cells][i];
                var right = self[\cells][(i + 1).wrap(0, self[\numCells] - 1)];
                var neighborhood = (left * 4) + (center * 2) + right;  // 0-7
                newCells[i] = (self[\rule] >> neighborhood) & 1;
            });
            self[\cells] = newCells;
            self[\generation] = self[\generation] + 1;
        },

        getGates: { |self|
            self[\cells].copy;
        },

        getValue: { |self, cellIndex|
            self[\cells][cellIndex.clip(0, self[\numCells] - 1)];
        },

        getCV: { |self|
            // Convert cell pattern to CV (binary to decimal, normalized)
            var val = 0;
            min(8, self[\numCells]).do({ |i|
                val = val + (self[\cells][i] * (2 ** i));
            });
            val / 255;
        },

        setRule: { |self, r|
            self[\rule] = r.clip(0, 255).asInteger;
        },

        seed: { |self, pattern|
            if(pattern.notNil) {
                self[\cells] = pattern;
            } {
                self[\cells] = Array.fill(self[\numCells], { 0 });
                self[\cells][(self[\numCells] / 2).asInteger] = 1;  // Single center cell
            };
            self[\generation] = 0;
        },

        reset: { |self|
            self.seed(nil);
        }
    );
    seq;
};

// ==========================================
// L-SYSTEM (Lindenmayer grammar)
// ==========================================
~SIBYL_LSYSTEM = { |axiom="F", rules=nil, depth=3|
    var seq = (
        axiom: axiom,
        rules: rules ?? { IdentityDictionary[\F -> "F+F-F-F+F"] },
        depth: depth,
        sequence: nil,
        pos: 0,
        // Character → note mapping
        charMap: IdentityDictionary[
            $F -> 0, $G -> 2, $A -> 4, $B -> 5,
            $+ -> 7, $- -> -7, $[ -> 12, $] -> -12
        ],
        noteOffset: 60,

        generate: { |self|
            var str = self[\axiom];
            self[\depth].clip(1, 8).do({
                var newStr = "";
                str.do({ |char|
                    var replacement = self[\rules][char];
                    if(replacement.notNil) {
                        newStr = newStr ++ replacement;
                    } {
                        newStr = newStr ++ char.asString;
                    };
                });
                str = newStr;
            });
            // Convert to note sequence
            self[\sequence] = Array.new;
            var currentNote = self[\noteOffset];
            str.do({ |char|
                var interval = self[\charMap][char];
                if(interval.notNil) {
                    currentNote = currentNote + interval;
                    self[\sequence] = self[\sequence].add(currentNote.clip(24, 108));
                };
            });
            if(self[\sequence].size == 0) {
                self[\sequence] = [60];
            };
        },

        advance: { |self|
            if(self[\sequence].isNil) { self.generate };
            self[\pos] = (self[\pos] + 1) % self[\sequence].size;
        },

        getNote: { |self|
            if(self[\sequence].isNil) { self.generate };
            self[\sequence][self[\pos]];
        },

        getValue: { |self|
            // Normalized 0-1
            (self.getNote - 24) / 84;
        },

        setRule: { |self, char, replacement|
            self[\rules][char] = replacement;
            self[\sequence] = nil;  // Invalidate
        },

        reset: { |self|
            self[\pos] = 0;
        }
    );
    seq;
};

// ==========================================
// BERNOULLI GATE (probability-based routing)
// ==========================================
SynthDef(\sibyl_bernoulli, {
    |inBus=0, outBusA=0, outBusB=1, probability=0.5|

    var trig, coin;
    trig = In.kr(inBus, 1);

    // Use TIRand for coin flip on each trigger
    coin = TIRand.kr(0, 1000, trig) < (probability.clip(0, 1) * 1000);

    Out.kr(outBusA, trig * coin);
    Out.kr(outBusB, trig * (1 - coin));
}).add;

// Audio-rate Bernoulli
SynthDef(\sibyl_bernoulli_ar, {
    |inBus=0, outBusA=0, outBusB=1, probability=0.5, trigBus=0|

    var sig, trig, coin;
    sig = In.ar(inBus, 1);
    trig = In.kr(trigBus, 1);

    coin = TIRand.kr(0, 1000, trig) < (probability.clip(0, 1) * 1000);

    Out.ar(outBusA, sig * coin);
    Out.ar(outBusB, sig * (1 - coin));
}).add;

// ==========================================
// COMPARATOR SEQUENCER (CV threshold → gate patterns)
// ==========================================
SynthDef(\sibyl_comparator_seq, {
    |inBus=0, outBus=0, threshold=0.5, hysteresis=0.01|

    var sig, gate;
    sig = In.kr(inBus, 1);
    gate = Schmidt.kr(sig, threshold - hysteresis.clip(0, 0.2), threshold + hysteresis.clip(0, 0.2));
    Out.kr(outBus, gate);
}).add;

// ==========================================
// OSC RESPONDERS FOR ALL SEQUENCERS
// ==========================================

// Global sequencer instances
~SIBYL_INSTANCES = IdentityDictionary.new;

OSCdef(\sibyl_create, { |msg|
    var type = msg[1].asSymbol;
    var name = msg[2].asSymbol;
    var instance;

    switch(type,
        \step, {
            var steps = msg[3] ? 16;
            var dir = msg[4] ? 0;
            instance = ~SIBYL_STEP.(steps.asInteger, dir.asInteger);
        },
        \euclidean, {
            var len = msg[3] ? 16;
            var fills = msg[4] ? 4;
            var rot = msg[5] ? 0;
            instance = ~SIBYL_EUCLIDEAN.(len.asInteger, fills.asInteger, rot.asInteger);
        },
        \turing, {
            var bits = msg[3] ? 8;
            var prob = msg[4] ? 0.5;
            instance = ~SIBYL_TURING.(bits.asInteger, prob.asFloat);
        },
        \markov, {
            var states = msg[3] ? 8;
            var temp = msg[4] ? 0.5;
            instance = ~SIBYL_MARKOV.(states.asInteger, temp.asFloat);
        },
        \automata, {
            var cells = msg[3] ? 16;
            var rule = msg[4] ? 30;
            instance = ~SIBYL_AUTOMATA.(cells.asInteger, rule.asInteger);
        },
        \lsystem, {
            var axiom = msg[3].asString;
            instance = ~SIBYL_LSYSTEM.(axiom);
        }
    );

    if(instance.notNil) {
        ~SIBYL_INSTANCES[name] = instance;
        "SIBYL: Created % '%'".format(type, name).postln;
    };
}, "/sibyl/create");

OSCdef(\sibyl_advance, { |msg|
    var name = msg[1].asSymbol;
    var inst = ~SIBYL_INSTANCES[name];
    if(inst.notNil) { inst.advance };
}, "/sibyl/advance");

OSCdef(\sibyl_get, { |msg|
    var name = msg[1].asSymbol;
    var outBusIdx = msg[2].asInteger;
    var inst = ~SIBYL_INSTANCES[name];
    if(inst.notNil) {
        var outBus = Bus(\control, outBusIdx, 1, s);
        outBus.set(inst.getValue);
    };
}, "/sibyl/get");

OSCdef(\sibyl_reset, { |msg|
    var name = msg[1].asSymbol;
    var inst = ~SIBYL_INSTANCES[name];
    if(inst.notNil) { inst.reset };
}, "/sibyl/reset");

"--- BRAHMA: SIBYL Sequencer Modules Online (8 modules) ---".postln;
)
