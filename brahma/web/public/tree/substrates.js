// ============================================================================
//  SUBSTRATES — the synthesizer of all things.
// ----------------------------------------------------------------------------
//  The Brahma engine was never about sound. AdamKadmon validates *trait maps*;
//  FSAP absorbs *any* donor identity; the 7-stage organism is a universal
//  metabolism — assimilate, wear, extract, transmute, re-express. Audio is
//  merely SUBSTRATE ZERO.
//
//  A substrate is a reality the one engine can synthesize. Each declares:
//    - four trait AXES (rhyming with AdamKadmon's canonical four:
//      spectral_profile · temporal_topology · modulation_graph ·
//      performance_response) cast into the substrate's own tongue, and
//    - a vocabulary of ORGANISMS, each seated on a Sephirah of the Tree.
//
//  The same Tree of Life expresses them all. That is the whole claim.
// ============================================================================

const Substrates = (() => {
    const LIST = [
        {
            id: "sound", key: "1", name: "SOUND", glyph: "♪",
            tagline: "absorb · mutate · re-express  TIMBRE",
            axes: ["Spectrum", "Envelope", "Modulation", "Play"],
            organisms: [
                { type: "Proteus",      seat: "chokmah", color: [0, 255, 255] },
                { type: "Relinquished", seat: "gevurah", color: [255, 0, 0] },
                { type: "Golem",        seat: "malkuth", color: [255, 165, 0] },
                { type: "Typhon",       seat: "binah",   color: [148, 0, 211] },
                { type: "AgentSmith",   seat: "hod",     color: [0, 255, 0] },
                { type: "Ditto",        seat: "netzach", color: [255, 255, 0] },
                { type: "Additive",     seat: "chesed",  color: [200, 255, 100] },
                { type: "Wavetable",    seat: "tiferet", color: [255, 200, 100] },
                { type: "PD",           seat: "yesod",   color: [100, 255, 200] },
                { type: "Granular",     seat: "yesod",   color: [220, 220, 220] },
                { type: "Formant",      seat: "binah",   color: [180, 100, 255] },
                { type: "WestCoast",    seat: "netzach", color: [255, 100, 100] },
                { type: "Subtractive",  seat: "gevurah", color: [100, 200, 255] },
                { type: "FM",           seat: "chokmah", color: [255, 100, 200] },
                { type: "Vector",       seat: "tiferet", color: [100, 180, 255] },
                { type: "Physical",     seat: "malkuth", color: [200, 150, 100] },
                { type: "Ableton",      seat: "hod",     color: [80, 120, 200] }
            ]
        },
        {
            id: "idea", key: "2", name: "IDEA", glyph: "✶",
            tagline: "absorb · mutate · re-express  THOUGHT",
            axes: ["Abstraction", "Development", "Implication", "Provocation"],
            organisms: [
                { type: "Axiom",     seat: "keter",   color: [255, 255, 240] },
                { type: "Insight",   seat: "chokmah", color: [180, 210, 255] },
                { type: "Theory",    seat: "binah",   color: [150, 110, 230] },
                { type: "Synthesis", seat: "chesed",  color: [120, 200, 255] },
                { type: "Critique",  seat: "gevurah", color: [255, 90, 90] },
                { type: "Thesis",    seat: "tiferet", color: [255, 215, 120] },
                { type: "Narrative", seat: "netzach", color: [120, 235, 170] },
                { type: "Model",     seat: "hod",     color: [255, 170, 90] },
                { type: "Metaphor",  seat: "yesod",   color: [200, 160, 255] },
                { type: "Praxis",    seat: "malkuth", color: [150, 220, 150] },
                { type: "Paradox",   seat: "tiferet", color: [255, 150, 200] },
                { type: "Heresy",    seat: "gevurah", color: [255, 60, 120] }
            ]
        },
        {
            id: "product", key: "3", name: "PRODUCT", glyph: "◆",
            tagline: "absorb · mutate · re-express  VALUE",
            axes: ["Utility", "Adoption", "Network", "Desire"],
            organisms: [
                { type: "Vision",       seat: "keter",   color: [240, 255, 250] },
                { type: "Spark",        seat: "chokmah", color: [150, 220, 255] },
                { type: "Architecture", seat: "binah",   color: [120, 140, 230] },
                { type: "Platform",     seat: "chesed",  color: [90, 200, 230] },
                { type: "Moat",         seat: "gevurah", color: [230, 80, 80] },
                { type: "Offering",     seat: "tiferet", color: [255, 210, 130] },
                { type: "Market",       seat: "netzach", color: [110, 230, 140] },
                { type: "Protocol",     seat: "hod",     color: [120, 200, 255] },
                { type: "Tool",         seat: "yesod",   color: [180, 180, 200] },
                { type: "Revenue",      seat: "malkuth", color: [120, 220, 120] }
            ]
        },
        {
            id: "cosmos", key: "4", name: "COSMOS", glyph: "✧",
            tagline: "absorb · mutate · re-express  WORLDS",
            axes: ["Order", "Expansion", "Gravity", "Emergence"],
            organisms: [
                { type: "Void",        seat: "keter",   color: [230, 235, 255] },
                { type: "Singularity", seat: "chokmah", color: [200, 220, 255] },
                { type: "Field",       seat: "binah",   color: [130, 100, 210] },
                { type: "Expansion",   seat: "chesed",  color: [100, 180, 255] },
                { type: "Gravity",     seat: "gevurah", color: [200, 70, 90] },
                { type: "Star",        seat: "tiferet", color: [255, 230, 160] },
                { type: "Life",        seat: "netzach", color: [120, 240, 150] },
                { type: "Mind",        seat: "hod",     color: [180, 160, 255] },
                { type: "Recurrence",  seat: "yesod",   color: [160, 200, 255] },
                { type: "World",       seat: "malkuth", color: [120, 200, 140] }
            ]
        }
    ];

    // Global index: every organism type → its seat & color, across all
    // substrates. Lets a live OSC stream from any reality resolve correctly.
    const INDEX = {};
    LIST.forEach(sub => sub.organisms.forEach(o => {
        INDEX[o.type] = { seat: o.seat, color: o.color, substrate: sub.id };
    }));

    let activeIdx = 0;

    function active() { return LIST[activeIdx]; }
    function setActive(i) { activeIdx = (i % LIST.length + LIST.length) % LIST.length; return active(); }
    function cycle(dir = 1) { return setActive(activeIdx + dir); }
    function byKey(k) {
        const i = LIST.findIndex(s => s.key === k);
        if (i >= 0) { activeIdx = i; return true; }
        return false;
    }

    function seatFor(type) { return (INDEX[type] && INDEX[type].seat) || "tiferet"; }
    function colorFor(type) { return (INDEX[type] && INDEX[type].color) || [255, 255, 255]; }

    // Shared source of truth: these are the JSON files loaded by AdamKadmon.
    // This loads schemas, not measured live traits or a synthetic SC readback.
    async function loadContracts(fetcher = fetch) {
        const contracts = await Promise.all(LIST.map(async sub => {
            const response = await fetcher(`/api/substrates/${sub.id}.json`);
            if (!response.ok) throw new Error(`Contract unavailable: ${sub.id}`);
            const contract = await response.json();
            if (contract.substrate !== sub.id || !Array.isArray(contract.axes) || contract.axes.length !== 4 ||
                !Array.isArray(contract.requiredKeys) || contract.requiredKeys.length !== 4) {
                throw new Error(`Invalid substrate contract: ${sub.id}`);
            }
            return contract;
        }));
        contracts.forEach((contract, i) => { LIST[i].contract = contract; LIST[i].axes = contract.axes; });
        return contracts;
    }

    if (typeof window !== "undefined" && typeof fetch === "function") {
        loadContracts().catch(error => console.error("Brahma substrate contract load failed:", error));
    }
    return { LIST, active, setActive, cycle, byKey, seatFor, colorFor, loadContracts };
})();
