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
      if (!source || !/^[a-f0-9]{64}$/.test(source.sha256) || source.id !== "sha256:" + source.sha256) fail("Invalid source identity");
      if (byId.has(source.id)) fail("Duplicate source identity");
      // Check encoded length before parsing a potentially large base64 string.
      if (typeof source.data !== "string" || source.data.length > Math.ceil(cap.maxSourceBytes / 3) * 4) fail("Audio exceeds project size limit");
      total += encodedSize(source.data);
      if (total > cap.maxSourceBytes) fail("Audio exceeds project size limit");
      const duration = number(source.duration, Number.MIN_VALUE, 86400, "source duration");
      const sampleRate = number(source.sampleRate, 8000, 384000, "sample rate", true);
      const channels = number(source.channels, 1, 32, "channels", true);
      decoded += Math.ceil(duration * sampleRate) * channels * 4;
      if (decoded > cap.maxDecodedBytes) fail("Decoded audio exceeds memory budget");
      if (!Array.isArray(source.slices) || !source.slices.length || source.slices.length > 128) fail("Invalid slices");
      const slices = source.slices.map(slice => {
        if (!slice || !Number.isFinite(slice.start) || !Number.isFinite(slice.end) ||
          slice.start < 0 || slice.end > duration || slice.end <= slice.start) fail("Invalid slice bounds");
        return { start: slice.start, end: slice.end };
      });
      const clean = { id: source.id, sha256: source.sha256,
        name: label(source.name, 1024, "source name"), mime: label(source.mime, 128, "source type"),
        data: source.data, duration, sampleRate, channels, slices };
      if (source.recipe !== undefined) clean.recipe = recipe(source.recipe);
      byId.set(source.id, clean);
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
    const settings = project.vessels === undefined ? [null, null, null, null, null] : project.vessels;
    if (!Array.isArray(settings) || settings.length !== 5) fail("Invalid project vessels");
    const vessels = settings.map(vessel);
    return { schema: SCHEMA, name, tempo, phase: project.phase, cycle, vessels,
      scene: { steps, tracks: 5, grid, tempo, phase: project.phase }, trackSources, sources };
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
    return validateProject(clean, overrides);
  }
  async function deserialize(text, overrides) {
    if (typeof text !== "string" || text.length > limits(overrides).maxProjectBytes ||
      new TextEncoder().encode(text).byteLength > limits(overrides).maxProjectBytes) fail("Project exceeds file size limit");
    let parsed;
    try { parsed = JSON.parse(text); } catch (_) { fail("Invalid project JSON"); }
    const project = validateProject(parsed, overrides);
    for (const source of project.sources) {
      if (await digest(sourceBytes(source)) !== source.sha256) fail("Source audio integrity check failed: " + source.name);
    }
    return project;
  }
  return { SCHEMA, DEFAULT_LIMITS, limits, createSource, sourceBytes, equalSlices, digest,
    validateProject, serialize, deserialize, replaceTrackSource, vessel };
});
