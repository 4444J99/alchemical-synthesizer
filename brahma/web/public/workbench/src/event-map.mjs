// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 4444J99
/**
 * event-map.mjs — Strudel hap → Brahma event translation.
 *
 * Kept free of DOM and scheduler imports so it can be unit-tested directly.
 *
 * The units matter and are not the obvious ones. Strudel's `Cyclist` calls
 * `defaultOutput(hap, deadline, duration, cps, t)` where:
 *   deadline  is a RELATIVE offset in seconds from now (targetTime - phase)
 *   duration  is ALREADY in seconds (hap.duration / cps)
 * Both are passed through unchanged here. Getting either wrong produces a pattern
 * that fires immediately and at the wrong length.
 *
 * Mapping is deliberately narrow and documented rather than clever:
 *   engine   a control `s` that matches a known Brahma module, else the default engine
 *   note     `note` as MIDI number or note name ("e3", "c#4", "eb2"), or `freq` as Hz
 *   velocity `velocity`, else `gain`, else 0.8
 *   params   other numeric controls passed through as Brahma param/value pairs
 */

export const DEFAULT_ENGINE = "prima_materia";
export const MAX_DUR_SECS = 30; // mirrors the engine's maxVoiceSecs and the gateway clamp
export const MIN_DUR_SECS = 0.02;

// Controls consumed by the mapping itself; everything else numeric is a param.
export const RESERVED = new Set([
  "note", "freq", "n", "s", "gain", "velocity", "dur",
  "legato", "clip", "cps", "unit", "id", "color"
]);

const clamp = (lo, hi, v) => Math.min(hi, Math.max(lo, v));

const SEMITONES = { c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11 };

function num(v) {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

/**
 * MIDI number from a Strudel note name, or null.
 *
 * Strudel hands over note names as strings ("e3"), not MIDI, until a sound output
 * converts them. Octave convention is C4 = 60 (so "c3" is 48), matching Tonal and
 * therefore Strudel itself. Accidentals: `#`/`s` sharp, `b`/`f` flat, doubled allowed.
 */
export function midiFromName(name) {
  const m = /^([a-gA-G])([#sbf]{0,2})(-?\d+)?$/.exec(String(name).trim());
  if (!m) return null;

  const base = SEMITONES[m[1].toLowerCase()];
  let accidental = 0;
  for (const ch of m[2].toLowerCase()) {
    if (ch === "#" || ch === "s") accidental += 1;
    else if (ch === "b" || ch === "f") accidental -= 1;
  }
  const octave = m[3] === undefined ? 4 : Number.parseInt(m[3], 10);
  return (octave + 1) * 12 + base + accidental;
}

/** MIDI note number from a hap value, or null when the hap names no pitch. */
export function noteOf(value) {
  const v = value || {};

  const note = v.note;
  if (typeof note === "number" && Number.isFinite(note)) {
    return clamp(0, 127, Math.round(note));
  }
  if (typeof note === "string") {
    const parsed = midiFromName(note);
    if (parsed !== null) return clamp(0, 127, parsed);
    const asNumber = Number(note);
    if (Number.isFinite(asNumber)) return clamp(0, 127, Math.round(asNumber));
  }

  const freq = num(v.freq);
  if (freq !== null && freq > 0) {
    return clamp(0, 127, Math.round(69 + 12 * Math.log2(freq / 440)));
  }
  return null;
}

/**
 * Translate one Strudel hap value into a Brahma event frame.
 * Returns null for values that carry no pitch (control-only patterns, silence).
 *
 * @param {object} value        hap.value
 * @param {object} opts
 * @param {number} opts.duration seconds, as supplied by the scheduler
 */
export function toEvent(value, { duration, id, engine, knownEngines = new Set() } = {}) {
  const note = noteOf(value);
  if (note === null) return null;

  const v = value || {};
  const sound = v.s === undefined ? null : String(v.s);
  const resolvedEngine = sound && knownEngines.has(sound) ? sound : (engine || DEFAULT_ENGINE);

  const gain = num(v.velocity) ?? num(v.gain) ?? 0.8;
  const dur = clamp(MIN_DUR_SECS, MAX_DUR_SECS, num(duration) ?? 1);

  const params = [];
  for (const [key, val] of Object.entries(v)) {
    if (RESERVED.has(key)) continue;
    const n = num(val);
    if (n === null) continue;
    params.push(key, n);
    if (params.length >= 16) break;
  }

  return {
    type: "event",
    id,
    engine: resolvedEngine,
    instance: id,
    note,
    vel: clamp(0, 1, gain),
    dur,
    params
  };
}
