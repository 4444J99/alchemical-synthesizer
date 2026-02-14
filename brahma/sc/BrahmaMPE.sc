/*
  BrahmaMPE: MIDI & MPE Voice Manager
  Handles MPE zone configuration, voice allocation,
  per-note expression (pitch bend, pressure, slide).
*/

BrahmaMPE {
    var <lowerZone;    // (masterCh: 0, memberChs: [1..15], numMembers: 15)
    var <upperZone;    // nil by default (single-zone MPE)
    var <voices;       // Array of voice states
    var <maxVoices;
    var <pitchBendRange; // Semitones (default ±48 for MPE, ±2 for standard)
    var <mpeEnabled;

    // Voice state: (channel, note, freq, velocity, pressure, slide, bendSemitones, gate, synthNode)
    classvar <defaultBendRange = 48;

    *new { |maxVoices=16, mpeEnabled=true|
        ^super.new.init(maxVoices, mpeEnabled);
    }

    init { |maxV, mpe|
        maxVoices = maxV;
        mpeEnabled = mpe;
        pitchBendRange = if(mpe) { defaultBendRange } { 2 };

        // Lower zone: ch 0 = master, ch 1-15 = member channels
        lowerZone = (
            masterCh: 0,
            memberChs: (1..15).asArray,
            numMembers: 15
        );
        upperZone = nil;

        voices = Array.fill(maxVoices, {
            (
                channel: nil,
                note: nil,
                freq: 440.0,
                velocity: 0.0,
                releaseVelocity: 0.0,
                pressure: 0.0,
                slide: 0.0,       // CC74
                bendSemitones: 0.0,
                gate: 0,
                synthNode: nil,
                bus: nil          // Control bus for per-voice CV
            )
        });
    }

    // ==========================================
    // ZONE CONFIGURATION
    // ==========================================
    setLowerZone { |numMembers=15|
        numMembers = numMembers.clip(1, 15);
        lowerZone[\numMembers] = numMembers;
        lowerZone[\memberChs] = (1..numMembers).asArray;
        "BrahmaMPE: Lower zone set to % member channels".format(numMembers).postln;
    }

    setUpperZone { |numMembers=0|
        if(numMembers > 0) {
            numMembers = numMembers.clip(1, 14);
            upperZone = (
                masterCh: 15,
                memberChs: ((15 - numMembers)..(14)).asArray,
                numMembers: numMembers
            );
            // Adjust lower zone to avoid overlap
            lowerZone[\numMembers] = 15 - numMembers - 1;
            lowerZone[\memberChs] = (1..lowerZone[\numMembers]).asArray;
            "BrahmaMPE: Upper zone set to % member channels".format(numMembers).postln;
        } {
            upperZone = nil;
            "BrahmaMPE: Upper zone disabled".postln;
        };
    }

    // Is this channel a member channel (not master)?
    isMemberChannel { |ch|
        if(lowerZone[\memberChs].includes(ch)) { ^true };
        if(upperZone.notNil and: { upperZone[\memberChs].includes(ch) }) { ^true };
        ^false;
    }

    // Which zone does this channel belong to?
    zoneForChannel { |ch|
        if(ch == lowerZone[\masterCh]) { ^\lowerMaster };
        if(lowerZone[\memberChs].includes(ch)) { ^\lower };
        if(upperZone.notNil) {
            if(ch == upperZone[\masterCh]) { ^\upperMaster };
            if(upperZone[\memberChs].includes(ch)) { ^\upper };
        };
        ^\none;
    }

    // ==========================================
    // VOICE ALLOCATION
    // ==========================================

    // Find a free voice or steal the oldest
    allocateVoice { |channel, note, velocity|
        var freeIdx = nil, oldestIdx = 0, oldestTime = inf;

        voices.do({ |v, i|
            if(v[\gate] == 0 and: { freeIdx.isNil }) {
                freeIdx = i;
            };
        });

        // If no free voice, steal (simple round-robin: take first active)
        if(freeIdx.isNil) {
            freeIdx = 0; // Could be smarter (oldest note, quietest, etc.)
            this.releaseVoice(freeIdx, 0);
        };

        voices[freeIdx][\channel] = channel;
        voices[freeIdx][\note] = note;
        voices[freeIdx][\velocity] = velocity / 127;
        voices[freeIdx][\pressure] = 0.0;
        voices[freeIdx][\slide] = 0.0;
        voices[freeIdx][\bendSemitones] = 0.0;
        voices[freeIdx][\gate] = 1;

        ^freeIdx;
    }

    // Find voice by channel + note
    findVoice { |channel, note|
        voices.do({ |v, i|
            if(v[\channel] == channel and: { v[\note] == note } and: { v[\gate] > 0 }) {
                ^i;
            };
        });
        ^nil;
    }

    // Find all voices on a channel (for MPE per-channel expression)
    findVoicesByChannel { |channel|
        var indices = List.new;
        voices.do({ |v, i|
            if(v[\channel] == channel and: { v[\gate] > 0 }) {
                indices.add(i);
            };
        });
        ^indices;
    }

    // Release a voice
    releaseVoice { |voiceIdx, releaseVelocity=0|
        if(voiceIdx < maxVoices) {
            voices[voiceIdx][\gate] = 0;
            voices[voiceIdx][\releaseVelocity] = releaseVelocity / 127;
            // Synth node release handled by caller
        };
    }

    // Update per-channel pressure (MPE: per-note aftertouch)
    setPressure { |channel, pressure|
        var indices = this.findVoicesByChannel(channel);
        indices.do({ |i|
            voices[i][\pressure] = pressure / 127;
        });
    }

    // Update per-channel slide (CC74)
    setSlide { |channel, value|
        var indices = this.findVoicesByChannel(channel);
        indices.do({ |i|
            voices[i][\slide] = value / 127;
        });
    }

    // Update per-channel pitch bend
    setBend { |channel, bendValue|
        // bendValue: 0-16383 (8192 = center)
        var semitones = (bendValue - 8192) / 8192 * pitchBendRange;
        var indices = this.findVoicesByChannel(channel);
        indices.do({ |i|
            voices[i][\bendSemitones] = semitones;
        });
    }

    // Get the effective frequency for a voice (note + bend + tuning offset)
    voiceFreq { |voiceIdx, scale=nil, rootHz=440.0|
        var v = voices[voiceIdx];
        var baseFreq;

        if(scale.notNil) {
            baseFreq = scale.degreeToFreq(v[\note] - 60, 4, rootHz);
        } {
            baseFreq = (v[\note]).midicps;
        };

        // Apply pitch bend
        ^baseFreq * (2 ** (v[\bendSemitones] / 12));
    }

    // Release all voices
    panic {
        voices.do({ |v, i|
            v[\gate] = 0;
            v[\pressure] = 0;
            v[\slide] = 0;
            v[\bendSemitones] = 0;
            if(v[\synthNode].notNil) {
                v[\synthNode].set(\gate, 0);
                v[\synthNode] = nil;
            };
        });
        "BrahmaMPE: All voices released (panic)".postln;
    }
}
