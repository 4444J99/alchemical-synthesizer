/* The same bounded sample voice renders live playback and offline loop exports. */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory(require("./sample-project.js"), require("./pattern.js"));
  else root.SampleAudio = factory(root.SampleProject, root.Pattern);
})(typeof self !== "undefined" ? self : this, function (M, P) {
  "use strict";
  const WAVES = ["sine", "triangle", "sawtooth", "square", "triangle"];
  function outputGraph(context, destination) {
    const gain = context.createGain(), limiter = context.createDynamicsCompressor();
    gain.gain.value = 0.7;
    limiter.threshold.value = -3; limiter.knee.value = 0; limiter.ratio.value = 20;
    limiter.attack.value = 0.003; limiter.release.value = 0.1;
    gain.connect(limiter); limiter.connect(destination);
    return gain;
  }
  class Renderer {
    constructor(context, destination, overrides) {
      this.context = context; this.destination = destination; this.limits = M.limits(overrides);
      this.entries = new Map(); this.voices = new Set(); this.generation = 0;
      this.meters = new Map();
    }
    trackBus(track) {
      if (!this.meters.has(track)) {
        const analyser = this.context.createAnalyser(); analyser.fftSize = 512;
        analyser.connect(this.destination);
        this.meters.set(track, { analyser, wave: new Float32Array(512) });
      }
      return this.meters.get(track).analyser;
    }
    level(track) {
      const meter = this.meters.get(track);
      if (!meter || !Array.from(this.voices).some(voice => voice.track === track)) return { rms: 0, peak: 0, wave: null };
      meter.analyser.getFloatTimeDomainData(meter.wave);
      let sum = 0, peak = 0;
      for (const value of meter.wave) { sum += value * value; peak = Math.max(peak, Math.abs(value)); }
      return { rms: Math.sqrt(sum / meter.wave.length), peak, wave: meter.wave };
    }
    async loadSources(sources, decoded) {
      if (sources.length > this.limits.maxSources) throw new Error("Source count exceeds project limit");
      const next = new Map(); let decodedBytes = 0;
      for (const source of sources) {
        if (next.has(source.id)) throw new Error("Duplicate sample source");
        const existing = this.entries.get(source.id);
        let buffer;
        try { buffer = existing ? existing.buffer : decoded && decoded.get(source.id) || await this.context.decodeAudioData(M.sourceBytes(source).buffer); }
        catch (_) { throw new Error("Cannot decode audio: " + source.name); }
        decodedBytes += buffer.length * buffer.numberOfChannels * 4;
        if (decodedBytes > this.limits.maxDecodedBytes) throw new Error("Decoded audio exceeds memory budget");
        if (Math.abs(buffer.duration - source.duration) > 0.02 || buffer.numberOfChannels !== source.channels) {
          throw new Error("Audio metadata does not match source: " + source.name);
        }
        next.set(source.id, { source, buffer });
      }
      this.entries = next;
    }
    trigger(track, ev, when) {
      const c = this.context, t = Math.max(c.currentTime, when + (ev.t || 0));
      let source, duration = Math.max(0.001, ev.dur), offset = 0, rate = 1;
      if (ev.sampleId != null) {
        const entry = this.entries.get(ev.sampleId);
        if (!entry) throw new Error("Sample unavailable: " + ev.sampleId);
        const slice = ev.sliceBounds || entry.source.slices[ev.slice];
        if (!slice || !Number.isFinite(slice.start) || !Number.isFinite(slice.end) || slice.start < 0 || slice.end <= slice.start || slice.end > entry.buffer.duration + 0.02) {
          throw new Error("Invalid sample slice");
        }
        source = c.createBufferSource(); source.buffer = entry.buffer;
        rate = Math.pow(2, (ev.note - 60) / 12);
        source.playbackRate.value = rate; offset = slice.start;
        duration = Math.min(duration, (slice.end - slice.start) / rate);
      } else {
        source = c.createOscillator(); source.type = WAVES[track % WAVES.length];
        source.frequency.value = 440 * Math.pow(2, (ev.note - 69) / 12);
      }
      const filter = c.createBiquadFilter(), envelope = c.createGain();
      filter.type = "lowpass"; filter.frequency.value = ev.sampleId ? 10000 : 400 + ev.gain * 4000;
      const gain = Math.max(0, Math.min(1, ev.gain)) * 0.5, fade = Math.min(0.005, duration / 4);
      envelope.gain.setValueAtTime(0, t);
      envelope.gain.linearRampToValueAtTime(gain, t + fade);
      envelope.gain.setValueAtTime(gain, t + duration - fade);
      envelope.gain.linearRampToValueAtTime(0, t + duration);
      source.connect(filter); filter.connect(envelope); envelope.connect(this.trackBus(track));
      const voice = { source, filter, envelope, track };
      const release = () => {
        source.disconnect(); filter.disconnect(); envelope.disconnect(); this.voices.delete(voice);
      };
      source.onended = release; this.voices.add(voice);
      if (ev.sampleId != null) source.start(t, offset, duration * rate);
      else source.start(t);
      source.stop(t + duration);
      return voice;
    }
    stopAll() {
      this.generation++;
      for (const voice of this.voices) {
        try { voice.source.stop(this.context.currentTime); } catch (_) { /* already ended */ }
        voice.source.disconnect(); voice.filter.disconnect(); voice.envelope.disconnect();
      }
      this.voices.clear();
    }
  }
  async function renderLoop(project, overrides) {
    const clean = M.validateProject(project, overrides), rate = 44100;
    const stepDur = 60 / clean.tempo / 4, duration = clean.scene.steps * stepDur;
    // Export exactly one cycle. Voices and effect tails crossing its end are cut
    // at the musical boundary, rather than adding time that drifts on repetition.
    const context = new OfflineAudioContext(2, Math.round(duration * rate), rate);
    const renderer = new Renderer(context, outputGraph(context, context.destination), overrides);
    await renderer.loadSources(clean.sources);
    for (let step = 0; step < clean.scene.steps; step++) {
      for (let track = 0; track < clean.scene.tracks; track++) {
        const rng = P.makeRng((step + 1) * (track + 1) * (clean.cycle + 1));
        for (const ev of P.expandCell(clean.scene.grid[track][step], stepDur, rng)) renderer.trigger(track, ev, step * stepDur);
      }
    }
    return context.startRendering();
  }
  function wavBytes(buffer) {
    const channels = buffer.numberOfChannels, frames = buffer.length;
    const bytes = new ArrayBuffer(44 + frames * channels * 2), view = new DataView(bytes);
    const text = (at, value) => { for (let i = 0; i < value.length; i++) view.setUint8(at + i, value.charCodeAt(i)); };
    text(0, "RIFF"); view.setUint32(4, bytes.byteLength - 8, true); text(8, "WAVEfmt ");
    view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, channels, true);
    view.setUint32(24, buffer.sampleRate, true); view.setUint32(28, buffer.sampleRate * channels * 2, true);
    view.setUint16(32, channels * 2, true); view.setUint16(34, 16, true); text(36, "data");
    view.setUint32(40, frames * channels * 2, true);
    const planes = Array.from({ length: channels }, (_, i) => buffer.getChannelData(i));
    let at = 44;
    for (let frame = 0; frame < frames; frame++) for (let ch = 0; ch < channels; ch++) {
      const value = Math.max(-1, Math.min(1, planes[ch][frame]));
      view.setInt16(at, Math.round(value * (value < 0 ? 32768 : 32767)), true); at += 2;
    }
    return bytes;
  }
  return { Renderer, outputGraph, renderLoop, wavBytes };
});
