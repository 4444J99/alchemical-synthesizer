/* Portable, local-only sample projects. No DOM, audio device, or server state. */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory(require("./material-model.js"));
  else root.SampleProject = factory(root.MaterialModel);
})(typeof self !== "undefined" ? self : this, function (Material) {
  "use strict";
  const SCHEMA = "brahma.sample-project.v1";
  const DEFAULT_LIMITS = Object.freeze({ maxSourceBytes: 64 * 1024 * 1024,
    maxProjectBytes: 90 * 1024 * 1024, maxDecodedBytes: 256 * 1024 * 1024, maxSources: 64 });
  function limits(overrides) { return Object.assign({}, DEFAULT_LIMITS, overrides); }
  function fail(message) { throw new Error(message); }
  function number(value, min, max, name, integer) {
    if (!Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value))) {
      fail("Invalid " + name);
    }
    return value;
  }
  function label(value, max, name) {
    if (typeof value !== "string" || !value.length || value.length > max) fail("Invalid " + name);
    return value;
  }
  function bytesToBase64(bytes) {
    let chunks = [];
    for (let i = 0; i < bytes.length; i += 16384) chunks.push(String.fromCharCode.apply(null, bytes.subarray(i, i + 16384)));
    return btoa(chunks.join(""));
  }
  function encodedSize(data) {
    if (typeof data !== "string" || !data.length || data.length % 4 ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(data)) fail("Invalid source audio encoding");
    return data.length / 4 * 3 - (data.endsWith("==") ? 2 : data.endsWith("=") ? 1 : 0);
  }
  function sourceBytes(source) {
    if (source.data == null) fail("Source audio is referenced, not embedded: " + (source.name || source.id));
    encodedSize(source.data);
    const binary = atob(source.data), bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
  async function digest(bytes) {
    const webCrypto = globalThis.crypto || (typeof require === "function" && require("node:crypto").webcrypto);
    if (!webCrypto || !webCrypto.subtle) fail("Sample projects require a secure page (localhost or HTTPS)");
    const hash = await webCrypto.subtle.digest("SHA-256", bytes);
    return Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2, "0")).join("");
  }
  function equalSlices(duration, count) {
    number(duration, Number.MIN_VALUE, 86400, "duration");
    number(count, 1, 128, "slice count", true);
    return Array.from({ length: count }, (_, i) => ({ start: duration * i / count, end: duration * (i + 1) / count }));
  }
  function recipe(value) {
    if (!value || value.schema !== "brahma.native-recipe.v1" ||
        typeof value.parentId !== "string" || !/^sha256:[a-f0-9]{64}$/.test(value.parentId) ||
        typeof value.module !== "string" || !/^[a-z][a-z0-9_]{1,80}$/.test(value.module) ||
        !value.params || typeof value.params !== "object" || Array.isArray(value.params) || Object.keys(value.params).length > 32) fail("Invalid native recipe");
    const params = {};
    for (const [key, v] of Object.entries(value.params)) {
      if (!/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/.test(key) || !Number.isFinite(v) || Math.abs(v) > 1000000) fail("Invalid recipe control");
      params[key] = v;
    }
    for (const key of ["inputSha256", "definitionSha256", "rackSha256"]) {
      if (typeof value[key] !== "string" || !/^[a-f0-9]{64}$/.test(value[key])) fail("Invalid recipe hash");
    }
    const clean = { schema: value.schema, parentId: value.parentId, module: value.module, params,
      inputSha256: value.inputSha256, definitionSha256: value.definitionSha256, rackSha256: value.rackSha256 };
    if (value.material !== undefined) {
      clean.material = Material.validate(value.material);
      if (!value.baseParams || !/^[a-f0-9]{64}$/.test(value.modelSha256 || "")) fail("Invalid material model receipt");
      clean.baseParams = Material.baseControls(value.module, value.baseParams);
      clean.modelSha256 = value.modelSha256;
    } else if (value.baseParams !== undefined || value.modelSha256 !== undefined) fail("Missing recipe material state");
    return clean;
  }
  function vessel(value) {
    if (value === null) return null;
    if (!value || typeof value.module !== "string" || !/^[a-z][a-z0-9_]{1,80}$/.test(value.module)) fail("Invalid vessel module");
    const params = Material.baseControls(value.module, value.params);
    const material = value.material == null ? null : Material.validate(value.material);
    if (material && !Material.describe(value.module).supported) fail("Unsupported vessel material mapping");
    return { module: value.module, params, material };
  }
  // A relative asset reference: where the bytes live outside the file, named
  // by a path that cannot escape the library (no absolute path, no `..`,
  // no backslash). The ref names the same bytes as the source identity.
  function assetRef(value) {
    if (!value || typeof value.path !== "string" || !value.path.length || value.path.length > 1024 ||
        value.path.startsWith("/") || value.path.includes("\\") ||
        value.path.split("/").some(part => part === "..") ||
        /[\u0000-\u001f]/.test(value.path) ||
        typeof value.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(value.sha256)) fail("Invalid asset reference");
    return { path: value.path, sha256: value.sha256 };
  }
  function cleanSlices(slices, duration) {
    if (!Array.isArray(slices) || !slices.length || slices.length > 128) fail("Invalid slices");
    return slices.map(slice => {
      if (!slice || !Number.isFinite(slice.start) || !Number.isFinite(slice.end) ||
        slice.start < 0 || slice.end > duration || slice.end <= slice.start) fail("Invalid slice bounds");
      return { start: slice.start, end: slice.end };
    });
  }
  // One source, structurally cleaned: identity, metadata, chop boundaries,
  // and recipe. Embedded sources carry base64 audio; a reference-only source
  // (data null + ref) names bytes the file does not hold. Budgets and the
  // digest check live with the caller, not here, so reopen() can salvage
  // one bad source without losing the session.
  function cleanSource(source, cap) {
    if (!source || !/^[a-f0-9]{64}$/.test(source.sha256) || source.id !== "sha256:" + source.sha256) fail("Invalid source identity");
    const referenced = source.data == null;
    let ref;
    if (referenced) {
      ref = assetRef(source.ref);
      if (ref.sha256 !== source.sha256) fail("Asset reference hash does not match source identity");
    } else {
      if (typeof source.data !== "string" || source.data.length > Math.ceil(cap.maxSourceBytes / 3) * 4) fail("Audio exceeds project size limit");
      encodedSize(source.data);
      if (source.ref !== undefined) {
        ref = assetRef(source.ref);
        if (ref.sha256 !== source.sha256) fail("Asset reference hash does not match source identity");
      }
    }
    const duration = number(source.duration, Number.MIN_VALUE, 86400, "source duration");
    const sampleRate = number(source.sampleRate, 8000, 384000, "sample rate", true);
    const channels = number(source.channels, 1, 32, "channels", true);
    const slices = cleanSlices(source.slices, duration);
    const clean = { id: source.id, sha256: source.sha256,
      name: label(source.name, 1024, "source name"), mime: label(source.mime, 128, "source type"),
      duration, sampleRate, channels, slices };
    if (referenced) { clean.data = null; clean.ref = ref; }
    else { clean.data = source.data; if (ref) clean.ref = ref; }
    if (source.recipe !== undefined) clean.recipe = recipe(source.recipe);
    return clean;
  }
  // One Golem sequencer track's slice routing, mirroring the SC track fields
  // (15_golem_sequencer.scd, plan steps 4-5): which chop of the track's
  // source sounds, the clip's native tempo, the playback rate, and the one
  // live transformation with its stretch controls. The SC wire uses 0 for
  // "unknown/auto"; the session uses null for the same thing.
  function sliceTrack(value, source) {
    if (value === null) return null;
    if (!value || typeof value !== "object") fail("Invalid slice track");
    if (!source) fail("Slice track without a track source");
    const slice = number(value.slice, 0, source.slices.length - 1, "slice track chop", true);
    const sourceTempo = value.sourceTempo == null || value.sourceTempo === 0 ? null :
      number(value.sourceTempo, 0.0001, 1000, "source tempo");
    const rate = value.rate == null ? 1.0 : number(value.rate, -4, 4, "slice playback rate");
    const transform = value.transform == null ? "none" : value.transform;
    if (transform !== "none" && transform !== "timestretch") fail("Invalid slice transform");
    const stretchRate = value.stretchRate == null || value.stretchRate === 0 ? null :
      number(value.stretchRate, 0.01, 4, "stretch rate");
    const stretchPitch = value.stretchPitch == null ? 1.0 : number(value.stretchPitch, 0.25, 4, "stretch pitch");
    const stretchGrain = value.stretchGrain == null ? 0.1 : number(value.stretchGrain, 0.01, 1, "stretch grain");
    return { slice, sourceTempo, rate, transform, stretchRate, stretchPitch, stretchGrain };
  }
  async function createSource(input, metadata, overrides) {
    const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
    if (!bytes.length || bytes.length > limits(overrides).maxSourceBytes) fail("Audio exceeds the source size limit");
    const sha256 = await digest(bytes);
    return { id: "sha256:" + sha256, sha256, name: label(metadata.name, 1024, "source name"),
      mime: metadata.mime || "application/octet-stream", data: bytesToBase64(bytes),
      duration: number(metadata.duration, Number.MIN_VALUE, 86400, "duration"),
      sampleRate: number(metadata.sampleRate, 8000, 384000, "sample rate", true),
      channels: number(metadata.channels, 1, 32, "channels", true),
      slices: equalSlices(metadata.duration, 8) };
  }
  // A named asset the session references by relative path but does not embed:
  // the library file the chop came from, kept as an explicit unresolved item
  // until its bytes are in the file. No digest is possible here — the hash
  // comes from the reference itself — so reopen() reports it missing rather
  // than verifying it.
  function createReference(metadata, overrides) {
    const ref = assetRef(metadata.ref);
    const duration = number(metadata.duration, Number.MIN_VALUE, 86400, "duration");
    return { id: "sha256:" + ref.sha256, sha256: ref.sha256, name: label(metadata.name, 1024, "source name"),
      mime: metadata.mime || "application/octet-stream", data: null, ref,
      duration,
      sampleRate: number(metadata.sampleRate, 8000, 384000, "sample rate", true),
      channels: number(metadata.channels, 1, 32, "channels", true),
      slices: metadata.slices === undefined ? equalSlices(duration, 8) : cleanSlices(metadata.slices, duration) };
  }
  function validateProject(project, overrides) {
    const cap = limits(overrides);
    if (!project || project.schema !== SCHEMA) fail("Invalid or unsupported project format");
    const name = label(project.name, 1024, "project name");
    const tempo = number(project.tempo, 60, 200, "tempo");
    if (!["manual", "auto", "readable", "cluster", "dispersal"].includes(project.phase)) fail("Invalid phase");
    const cycle = number(project.cycle, 0, Number.MAX_SAFE_INTEGER, "cycle", true);
    if (!Array.isArray(project.sources) || project.sources.length > cap.maxSources) fail("Source count exceeds project limit");
    const byId = new Map();
    let total = 0, decoded = 0;
    const sources = project.sources.map(source => {
      if (source && byId.has(source.id)) fail("Duplicate source identity");
      const clean = cleanSource(source, cap);
      if (byId.has(clean.id)) fail("Duplicate source identity");
      if (clean.data != null) {
        total += encodedSize(clean.data);
        if (total > cap.maxSourceBytes) fail("Audio exceeds project size limit");
        decoded += Math.ceil(clean.duration * clean.sampleRate) * clean.channels * 4;
        if (decoded > cap.maxDecodedBytes) fail("Decoded audio exceeds memory budget");
      }
      byId.set(clean.id, clean);
      return clean;
    });
    for (const source of sources) {
      const visited = new Set([source.id]); let current = source;
      while (current.recipe) {
        const parent = byId.get(current.recipe.parentId);
        if (!parent || visited.has(parent.id)) fail("Invalid native recipe parent or cycle");
        visited.add(parent.id); current = parent;
      }
    }
    const scene = project.scene;
    if (!scene || scene.tracks !== 5 || !Array.isArray(scene.grid) || scene.grid.length !== 5) fail("Invalid scene grid");
    const steps = number(scene.steps, 1, 128, "step count", true);
    const grid = scene.grid.map(row => {
      if (!Array.isArray(row) || row.length !== steps) fail("Invalid scene grid row");
      return row.map(cell => {
        if (cell === null) return null;
        if (!cell || typeof cell !== "object") fail("Invalid pattern cell");
        const note = number(cell.note, 0, 127, "note");
        const vel = number(cell.vel, 0, 1, "velocity");
        if (!["", "RT", "ST", "OV", "HU", "DN"].includes(cell.cmd)) fail("Invalid pattern command");
        const amt = number(cell.amt, 0, 16, "command amount");
        const clean = { note, vel, cmd: cell.cmd, amt };
        if (cell.sampleId != null) {
          const source = byId.get(cell.sampleId);
          if (!source) fail("Missing sample source for pattern cell");
          clean.sampleId = source.id;
          clean.slice = number(cell.slice, 0, source.slices.length - 1, "slice reference", true);
        } else if (cell.slice != null) fail("Missing sample source for slice");
        return clean;
      });
    });
    if (!Array.isArray(project.trackSources) || project.trackSources.length !== 5) fail("Invalid track sources");
    const trackSources = project.trackSources.map(id => {
      if (id !== null && !byId.has(id)) fail("Missing track sample source");
      return id;
    });
    // Per-track slice routing for the live SC sequencer (plan steps 4-5).
    // Sessions saved before step 6 carry no sliceTracks and default to five
    // unbound tracks; a binding always needs its track's source present.
    const sliceTracksInput = project.sliceTracks === undefined ? [null, null, null, null, null] : project.sliceTracks;
    if (!Array.isArray(sliceTracksInput) || sliceTracksInput.length !== 5) fail("Invalid slice tracks");
    const sliceTracks = sliceTracksInput.map((entry, i) =>
      sliceTrack(entry, entry == null ? null : byId.get(trackSources[i])));
    const settings = project.vessels === undefined ? [null, null, null, null, null] : project.vessels;
    if (!Array.isArray(settings) || settings.length !== 5) fail("Invalid project vessels");
    const vessels = settings.map(vessel);
    return { schema: SCHEMA, name, tempo, phase: project.phase, cycle, vessels,
      scene: { steps, tracks: 5, grid, tempo, phase: project.phase }, trackSources, sliceTracks, sources };
  }
  function serialize(project, overrides) {
    const text = JSON.stringify(validateProject(project, overrides));
    if (new TextEncoder().encode(text).byteLength > limits(overrides).maxProjectBytes) fail("Project exceeds file size limit");
    return text;
  }
  function replaceTrackSource(project, track, fromId, toId, overrides) {
    const clean = validateProject(project, overrides);
    number(track, 0, 4, "track", true);
    if (!clean.sources.some(source => source.id === toId)) fail("Missing replacement source");
    clean.trackSources[track] = toId;
    clean.scene.grid[track] = clean.scene.grid[track].map(cell => cell && cell.sampleId === fromId ?
      Object.assign({}, cell, { sampleId: toId }) : cell);
    // A slice-track binding survives the swap only while its chop exists in
    // the new source; the binding was to the old source's chop, so an
    // out-of-range chop unbinds the track instead of reopening broken.
    const next = clean.sources.find(source => source.id === toId);
    if (clean.sliceTracks[track] != null && clean.sliceTracks[track].slice >= next.slices.length) clean.sliceTracks[track] = null;
    return validateProject(clean, overrides);
  }
  async function deserialize(text, overrides) {
    if (typeof text !== "string" || text.length > limits(overrides).maxProjectBytes ||
      new TextEncoder().encode(text).byteLength > limits(overrides).maxProjectBytes) fail("Project exceeds file size limit");
    let parsed;
    try { parsed = JSON.parse(text); } catch (_) { fail("Invalid project JSON"); }
    const project = validateProject(parsed, overrides);
    for (const source of project.sources) {
      // A referenced source is explicitly unresolved, not corrupt: its bytes
      // are not in the file, so there is nothing to verify. reopen() reports
      // it missing; strict reopening keeps it named so the caller can decide.
      if (source.data == null) continue;
      if (await digest(sourceBytes(source)) !== source.sha256) fail("Source audio integrity check failed: " + source.name);
    }
    return project;
  }
  // Tolerant reopen (plan step 6): a session with a missing or corrupt asset
  // still opens. Each bad source is reported — integrity failure, referenced
  // but not embedded, recipe parent gone, duplicate — and the notes, track
  // bindings, and slice bindings that pointed at it are dropped, so the
  // returned project is the actual playable state. A structurally malformed
  // session (bad grid, bad tempo, no schema) still throws: that is not a
  // missing asset, it is a broken file. Strict deserialize() is unchanged.
  async function reopen(text, overrides) {
    const cap = limits(overrides);
    if (typeof text !== "string" || text.length > cap.maxProjectBytes ||
      new TextEncoder().encode(text).byteLength > cap.maxProjectBytes) fail("Project exceeds file size limit");
    let parsed;
    try { parsed = JSON.parse(text); } catch (_) { fail("Invalid project JSON"); }
    if (!parsed || parsed.schema !== SCHEMA) fail("Invalid or unsupported project format");
    const missing = [];
    const kept = [];
    const seen = new Set();
    for (const source of (Array.isArray(parsed.sources) ? parsed.sources : [])) {
      if (source && typeof source.id === "string" && seen.has(source.id)) {
        missing.push({ id: source.id, name: source.name || source.id, reason: "duplicate source identity" });
        continue;
      }
      if (source && typeof source.id === "string") seen.add(source.id);
      try {
        const clean = cleanSource(source, cap);
        if (clean.data == null) {
          missing.push({ id: clean.id, name: clean.name, reason: "referenced but not embedded", ref: clean.ref.path });
          continue;
        }
        if (await digest(sourceBytes(clean)) !== clean.sha256) {
          missing.push({ id: clean.id, name: clean.name, reason: "source audio integrity check failed" });
          continue;
        }
        kept.push(clean);
      } catch (error) {
        missing.push({ id: (source && source.id) || "unknown", name: (source && source.name) || "unknown",
          reason: error && error.message ? error.message : "invalid source" });
      }
    }
    // A recipe child whose parent did not survive is missing too; cascade
    // until every kept source's parent is kept.
    const keptById = new Map(kept.map(s => [s.id, s]));
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = kept.length - 1; i >= 0; i--) {
        const parentId = kept[i].recipe && kept[i].recipe.parentId;
        if (parentId && !keptById.has(parentId)) {
          missing.push({ id: kept[i].id, name: kept[i].name, reason: "recipe parent missing" });
          keptById.delete(kept[i].id); kept.splice(i, 1); changed = true;
        }
      }
    }
    const missingIds = new Set(missing.map(m => m.id));
    const droppedCells = [];
    if (parsed.scene && Array.isArray(parsed.scene.grid)) {
      parsed.scene.grid.forEach((row, track) => {
        if (!Array.isArray(row)) return;
        row.forEach((cell, step) => {
          if (cell && cell.sampleId != null && missingIds.has(cell.sampleId)) {
            droppedCells.push({ track, step, sampleId: cell.sampleId, slice: cell.slice == null ? null : cell.slice });
            row[step] = null;
          }
        });
      });
    }
    const droppedTrackSources = [];
    const trackSources = Array.isArray(parsed.trackSources) ? parsed.trackSources.slice() : [];
    const origTrackSources = trackSources.slice();
    trackSources.forEach((id, track) => {
      if (id != null && missingIds.has(id)) { droppedTrackSources.push({ track, sampleId: id }); trackSources[track] = null; }
    });
    const droppedSliceTracks = [];
    const sliceTracks = Array.isArray(parsed.sliceTracks) ? parsed.sliceTracks.slice() : [null, null, null, null, null];
    sliceTracks.forEach((entry, track) => {
      if (entry != null && trackSources[track] == null) {
        droppedSliceTracks.push({ track, sampleId: origTrackSources[track] || null });
        sliceTracks[track] = null;
      }
    });
    const project = validateProject(Object.assign({}, parsed,
      { sources: kept, trackSources, sliceTracks }), overrides);
    return { project, report: { missing, droppedCells, droppedTrackSources, droppedSliceTracks } };
  }
  // The OSC messages that restore the live SC sequencer's slice tracks from
  // a saved session (15_golem_sequencer.scd): bind each slice track to its
  // chop, then its playback rate, transformation, and stretch controls. A
  // track with no slice binding sends nothing; a plain (\none) track sends
  // only the bind (and its rate, when it is not 1.0). The browser sends
  // these on reopen when its OSC bridge is connected.
  function sliceTrackMessages(project, overrides) {
    const clean = validateProject(project, overrides);
    const messages = [];
    clean.sliceTracks.forEach((entry, track) => {
      if (!entry) return;
      messages.push({ address: "/golem/slice/bind",
        args: [track, entry.slice, entry.sourceTempo == null ? 0 : entry.sourceTempo] });
      if (entry.rate !== 1.0) messages.push({ address: "/golem/slice/rate", args: [track, entry.rate] });
      if (entry.transform !== "none") {
        messages.push({ address: "/golem/slice/transform", args: [track, entry.transform] });
        messages.push({ address: "/golem/slice/stretch",
          args: [track, entry.stretchRate == null ? 0 : entry.stretchRate, entry.stretchPitch, entry.stretchGrain] });
      }
    });
    return messages;
  }
  return { SCHEMA, DEFAULT_LIMITS, limits, createSource, createReference, sourceBytes, equalSlices, digest,
    validateProject, serialize, deserialize, reopen, sliceTrackMessages, replaceTrackSource, vessel };
});
