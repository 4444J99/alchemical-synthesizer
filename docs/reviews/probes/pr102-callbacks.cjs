// Manual regression probe for the reviewed PR102 snapshot; expected to fail before repair.
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
if (!process.argv[2]) throw new Error('Usage: node pr102-callbacks.cjs path/to/sample-controls.js');
const file = path.resolve(process.argv[2]);
const elements = new Map();
function element(id = '') {
  return { id, value: id === 'sample-track' ? '0' : '', children: [], events: {}, dataset: {}, clientWidth: 300,
    addEventListener(name, action) { this.events[name] = action; },
    replaceChildren(...children) { this.children = children; },
    appendChild(child) { this.children.push(child); }, add(child) { this.children.push(child); },
    setAttribute() {}, getContext() { return { clearRect() {} }; }
  };
}
const get = id => elements.get(id) || (elements.set(id, element(id)), elements.get(id));
const project = { name: 'isolated comparison', sources: [
  { id: 'original', name: 'original', duration: 4, slices: [{start: 0, end: 4}] },
  { id: 'current', name: 'current', duration: 4, slices: [{start: 1, end: 2}], recipe: {parentId: 'original'} }
], trackSources: ['current'], vessels: [null] };
let options, requested = [], rendererRequests = 0;
const active = {
  generation: 0, entries: new Map(), context: { currentTime: 0, resume: async () => {} },
  level: () => ({rms: 0.4, peak: 0.7, wave: [0.2]}),
  loadSources: async () => {}, trigger: (track, event) => requested.push({track, event})
};
const window = {
  Pattern: { TRACKS: ['one'] }, SampleAudio: {},
  SampleProject: { limits: () => ({maxProjectBytes: 10000}), deserialize: async () => project },
  addEventListener() {},
  NativeControls: { attach(value) { options = value; return {validate() {}, cancel() {}, refresh() {}}; } }
};
const context = { window, document: { getElementById: get, createElement: () => element(), querySelectorAll: () => [] },
  Option: function(text, value) { this.text = text; this.value = value; }, console,
  setTimeout, clearTimeout, Uint8Array, Map, Array, Number, Math };
vm.runInNewContext(fs.readFileSync(file, 'utf8'), context, {filename: file, timeout: 1000});
window.SampleControls.attach({
  renderer: () => { rendererRequests++; return active; },
  stop: () => active.generation++, local() {}, restore() {}, scene: () => ({}), transport: () => ({})
});
(async () => {
  const initialLevel = options.level(0);
  const initialRequests = rendererRequests;
  get('open-project').events.change({target: {files: [{size: 1, text: async () => '{}'}], value: 'fixture'}});
  await new Promise(resolve => setImmediate(resolve));
  assert.match(get('sample-status').textContent, /^Opened /);
  await options.audition(true);
  const result = {
    source: 'PR102 de89004982de728126de463c43a08a0cef94d680',
    scope: 'actual SampleControls callbacks in isolated DOM/audio stubs; not real browser/audio acceptance',
    meter: {active: active.level(0), observed: initialLevel, rendererRequestsBeforeSampleActivity: initialRequests},
    comparison: {currentChop: project.sources[1].slices[0], retainedOriginalChop: project.sources[0].slices[0], requestedOriginalEvent: requested[0].event}
  };
  console.log(JSON.stringify(result, null, 2));
  const failures = [];
  if (initialLevel.rms !== active.level(0).rms) failures.push('active renderer meter was replaced by zero');
  if (requested[0].event.dur !== 1) failures.push('original audition used a 4-second retained chop instead of the current 1-second comparison range');
  assert.deepEqual(failures, [], failures.join('; '));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
