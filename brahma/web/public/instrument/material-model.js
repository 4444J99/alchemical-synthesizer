/* One versioned artistic material model for browser preview and native rendering. */
(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
    const dir = path.resolve(__dirname, "../../../../forge");
    const materials = fs.readFileSync(path.join(dir, "materials.json"));
    const controls = fs.readFileSync(path.join(dir, "native-controls.json"));
    module.exports = factory({ library: JSON.parse(materials), controls: JSON.parse(controls),
      sha256: crypto.createHash("sha256").update(materials).update("\n").update(controls).digest("hex") });
  } else root.MaterialModel = factory(root.BrahmaMaterialLibrary);
})(typeof self !== "undefined" ? self : this, function (payload) {
  "use strict";
  const SCHEMA = "brahma.material-state.v1";
  if (!payload || payload.library.schema !== "brahma.material-library.v1") throw new Error("Material library unavailable");
  const library = payload.library;
  const own = (object, key) => Object.hasOwn(object, key);
  function numeric(value, min, max, label) {
    if (!Number.isFinite(value) || value < min || value > max) throw new Error("Invalid material " + label);
    return value;
  }
  const rounded = value => Math.floor(value * 1e6 + 0.5) / 1e6;
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  function validate(state) {
    if (!state || state.schema !== SCHEMA || state.modelVersion !== library.version) throw new Error("Unsupported material version");
    if (typeof state.phase !== "string" || !own(library.phases, state.phase)) throw new Error("Invalid material phase");
    const amount = numeric(state.amount, 0, 1, "amount");
    if (!Array.isArray(state.composition) || !state.composition.length || state.composition.length > 4) throw new Error("Invalid material composition");
    const ids = new Set();
    const composition = state.composition.map(component => {
      if (!component || typeof component.id !== "string" || !own(library.materials, component.id) || ids.has(component.id)) throw new Error("Invalid material composition");
      ids.add(component.id);
      return { id: component.id, fraction: numeric(component.fraction, Number.MIN_VALUE, 1, "fraction") };
    }).sort((a, b) => a.id < b.id ? -1 : 1);
    if (Math.abs(composition.reduce((sum, component) => sum + component.fraction, 0) - 1) > 1e-6) throw new Error("Material fractions must sum to one");
    return { schema: SCHEMA, modelVersion: library.version, phase: state.phase, amount, composition };
  }
  function baseControls(moduleName, values = {}) {
    if (!values || typeof values !== "object" || Array.isArray(values)) throw new Error("Invalid native controls");
    const specs = payload.controls[moduleName] || {}, clean = {};
    for (const [key, value] of Object.entries(values)) {
      if (!own(specs, key)) throw new Error("Unsupported native control: " + key);
      const [, min, max, step] = specs[key];
      numeric(value, min, max, "control range: " + key);
      if (step === 1 && !Number.isInteger(value)) throw new Error("Native control must be an integer: " + key);
    }
    for (const [key, spec] of Object.entries(specs)) clean[key] = own(values, key) ? values[key] : spec[4];
    return clean;
  }
  function resolve(moduleName, values, state) {
    if (!own(library.profiles, moduleName)) throw new Error("Unsupported material mapping: " + moduleName);
    const material = validate(state), params = baseControls(moduleName, values), properties = {};
    const phase = library.phases[material.phase];
    for (const property of Object.keys(phase)) {
      const mixed = material.composition.reduce((sum, component) =>
        sum + library.materials[component.id].properties[property] * component.fraction, 0);
      properties[property] = rounded(clamp(mixed + phase[property], 0, 1));
    }
    for (const [control, [property, span]] of Object.entries(library.profiles[moduleName].targets)) {
      const [, min, max, step] = payload.controls[moduleName][control];
      const value = clamp(params[control] + (properties[property] - 0.5) * span * material.amount, min, max);
      params[control] = step === 1 ? Math.floor(value + 0.5) : rounded(value);
    }
    return { material, properties, params, modelSha256: payload.sha256 };
  }
  function describe(moduleName) {
    const profile = own(library.profiles, moduleName) && library.profiles[moduleName];
    return profile ? { supported: true, claim: profile.claim, targets: profile.targets, modelSha256: payload.sha256 } :
      { supported: false, claim: "Material response is not mapped. Use the native patch unchanged; original behavior acceptance remains unmeasured.", targets: {}, modelSha256: payload.sha256 };
  }
  function freeze(object) { Object.values(object).forEach(value => { if (value && typeof value === "object") freeze(value); }); return Object.freeze(object); }
  freeze(payload);
  return { SCHEMA, validate, baseControls, resolve, describe, payload };
});
