/* File, waveform, and project controls for the existing instrument. */
(function () {
  "use strict";
  const M = window.SampleProject, A = window.SampleAudio, P = window.Pattern;
  const $ = id => document.getElementById(id);
  window.SampleControls = { attach(bridge) {
    const caps = M.limits(window.BRAHMA_SAMPLE_LIMITS);
    let sources = [], trackSources = P.TRACKS.map(() => null), selectedSlice = 0, busy = false;
    let renderer = null;
    let native = null, revision = 0;
    function invalidateNative() { revision++; if (native) native.cancel(); }
    const audio = () => renderer || (renderer = bridge.renderer());
    const track = () => Number($("sample-track").value);
    const selectedSource = () => sources.find(s => s.id === trackSources[track()]);
    const report = (message, error) => {
      $("sample-status").textContent = message;
      $("sample-status").className = error ? "error" : "";
    };
    function snapshot() {
      const transport = bridge.transport();
      return M.validateProject({ schema: M.SCHEMA, name: $("project-name").value.trim() || "Brahma session",
        tempo: transport.tempo, phase: transport.phase, cycle: transport.cycle,
        scene: bridge.scene(), trackSources, sources }, caps);
    }
    function download(bytes, name, type) {
      const url = URL.createObjectURL(new Blob([bytes], { type }));
      const link = document.createElement("a"); link.href = url; link.download = name;
      document.body.appendChild(link); link.click(); link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30000);
    }
    const filename = () => ($("project-name").value.trim() || "Brahma session").replace(/[^a-zA-Z0-9_-]+/g, "-").slice(0, 100);
    async function operation(message, action) {
      if (busy) return;
      busy = true; report(message);
      const controls = Array.from(document.querySelectorAll("button,input,select")).filter(el => el.id !== "stop");
      controls.forEach(el => { el.disabled = true; });
      try { await action(); }
      catch (error) { report(error.message || String(error), true); }
      finally { busy = false; controls.forEach(el => { el.disabled = false; }); renderEditor(); }
    }
    function drawWaveform() {
      const canvas = $("waveform"), ctx = canvas.getContext("2d"), source = selectedSource();
      const width = canvas.width = Math.max(300, Math.round(canvas.clientWidth)), height = canvas.height = 100;
      ctx.clearRect(0, 0, width, height);
      const entry = source && renderer && renderer.entries.get(source.id);
      if (!entry) return;
      const data = entry.buffer.getChannelData(0), bucket = data.length / width;
      ctx.strokeStyle = "#7ba7ff"; ctx.beginPath();
      for (let x = 0; x < width; x++) {
        let peak = 0;
        const first = Math.floor(x * bucket), end = Math.min(data.length, Math.ceil((x + 1) * bucket));
        for (let i = first; i < end; i += Math.max(1, Math.floor(bucket / 64))) peak = Math.max(peak, Math.abs(data[i]));
        ctx.moveTo(x, height / 2 - peak * 45); ctx.lineTo(x, height / 2 + peak * 45);
      }
      ctx.stroke();
      source.slices.forEach((slice, i) => {
        const x = slice.start / source.duration * width, end = slice.end / source.duration * width;
        if (i === selectedSlice) { ctx.fillStyle = "#ffcf6b33"; ctx.fillRect(x, 0, end - x, height); }
        ctx.strokeStyle = i === selectedSlice ? "#ffcf6b" : "#6bd6ff55";
        ctx.strokeRect(x, 1, end - x, height - 2);
      });
    }
    function renderEditor() {
      const source = selectedSource(), chops = $("chops"); chops.replaceChildren();
      if (source) selectedSlice = Math.min(selectedSlice, source.slices.length - 1);
      $("slice-start").disabled = $("slice-end").disabled = $("apply-slice").disabled = !source || busy;
      $("slice-start").value = source ? source.slices[selectedSlice].start.toFixed(3) : "";
      $("slice-end").value = source ? source.slices[selectedSlice].end.toFixed(3) : "";
      if (source) source.slices.forEach((slice, i) => {
        const button = document.createElement("button"); button.type = "button";
        button.textContent = String(i + 1); button.dataset.slice = i;
        button.setAttribute("aria-label", "Chop " + (i + 1) + ": " + slice.start.toFixed(3) + " to " + slice.end.toFixed(3) + " seconds");
        button.setAttribute("aria-pressed", String(i === selectedSlice)); button.disabled = busy;
        button.addEventListener("click", async () => {
          selectedSlice = i; renderEditor();
          try {
            const engine = audio(), generation = engine.generation, trackIndex = track();
            await engine.context.resume();
            if (engine.generation !== generation) return;
            bridge.local();
            engine.trigger(trackIndex, { sampleId: source.id, slice: i, note: 60, gain: 0.8, dur: slice.end - slice.start, t: 0 }, engine.context.currentTime);
          } catch (e) { report(e.message, true); }
        });
        chops.appendChild(button);
      });
      drawWaveform();
    }
    function renderSources() {
      const select = $("sample-source"); select.replaceChildren(new Option("Synth voice", ""));
      sources.forEach(source => select.add(new Option(source.name, source.id)));
      select.value = trackSources[track()] || ""; renderEditor();
      if (native) native.refresh(true);
    }
    P.TRACKS.forEach((name, i) => $("sample-track").add(new Option(name, String(i))));
    $("sample-track").addEventListener("change", () => { invalidateNative(); selectedSlice = 0; renderSources(); });
    $("sample-source").addEventListener("change", () => {
      invalidateNative();
      trackSources[track()] = $("sample-source").value || null; selectedSlice = 0; renderEditor();
      if (native) native.refresh(true);
    });
    $("apply-slice").addEventListener("click", () => {
      const source = selectedSource(); if (!source) return;
      try {
        const start = Number($("slice-start").value), end = Number($("slice-end").value);
        if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start || end > source.duration) throw new Error("Chop must end after its start and stay inside the source");
        bridge.stop(); source.slices[selectedSlice] = { start, end }; renderEditor();
        report("Chop " + (selectedSlice + 1) + " updated. Place it in the grid.");
      } catch (e) { report(e.message, true); }
    });
    $("audio-file").addEventListener("change", event => {
      const file = event.target.files[0]; if (!file) return;
      invalidateNative();
      operation("Loading audio...", async () => {
        if (file.size > caps.maxSourceBytes) throw new Error("Audio exceeds the source size limit");
        const bytes = new Uint8Array(await file.arrayBuffer()), engine = audio();
        const hash = await M.digest(bytes), existing = sources.find(s => s.sha256 === hash);
        let buffer, source = existing;
        if (!existing) {
          try { buffer = await engine.context.decodeAudioData(bytes.slice().buffer); }
          catch (_) { throw new Error("Cannot decode this audio file. Try WAV, MP3, or another browser-supported format."); }
          if (buffer.length * buffer.numberOfChannels * 4 > caps.maxDecodedBytes) throw new Error("Decoded audio exceeds memory budget");
          source = await M.createSource(bytes, { name: file.name, mime: file.type || "application/octet-stream",
            duration: buffer.duration, sampleRate: buffer.sampleRate, channels: buffer.numberOfChannels }, caps);
        }
        const candidate = snapshot();
        if (!existing) candidate.sources.push(source);
        candidate.trackSources[track()] = source.id;
        const checked = M.validateProject(candidate, caps);
        await engine.loadSources(checked.sources, new Map([[source.id, buffer]]));
        bridge.stop(); sources = checked.sources; trackSources = checked.trackSources;
        selectedSlice = 0; bridge.local(); renderSources();
        report((existing ? "Loaded existing source: " : "Loaded ") + file.name + ". Select a chop, then place it in the grid.");
      }).finally(() => { event.target.value = ""; });
    });
    $("freeze").addEventListener("click", () => operation("Saving project...", async () => {
      download(M.serialize(snapshot(), caps), filename() + ".brahma.json", "application/json");
      report("Saved project with its source audio, chops, and pattern.");
    }));
    $("open-project").addEventListener("change", event => {
      const file = event.target.files[0]; if (!file) return;
      invalidateNative();
      operation("Opening project...", async () => {
        if (file.size > caps.maxProjectBytes) throw new Error("Project exceeds file size limit");
        const project = await M.deserialize(await file.text(), caps);
        await audio().loadSources(project.sources);
        bridge.stop(); sources = project.sources; trackSources = project.trackSources;
        $("project-name").value = project.name; $("sample-track").value = "0"; selectedSlice = 0;
        bridge.restore(project); renderSources();
        report("Opened " + project.name + ". Ready to play; transport is stopped.");
      }).finally(() => { event.target.value = ""; });
    });
    $("export-loop").addEventListener("click", () => operation("Rendering current loop...", async () => {
      const rendered = await A.renderLoop(snapshot(), caps);
      download(A.wavBytes(rendered), filename() + "-loop.wav", "audio/wav");
      report("Exported the current loop as a stereo WAV.");
    }));
    window.addEventListener("resize", drawWaveform);
    renderSources();
    function nativeContext() {
      const source = selectedSource(); let parent = source;
      while (parent && parent.recipe) parent = sources.find(item => item.id === parent.recipe.parentId);
      return { source, parent, track: track(), revision };
    }
    async function replace(target, source, buffer) {
      if (revision !== target.revision || track() !== target.track || !selectedSource() || selectedSource().id !== target.source.id) throw new Error("Native target changed; current project preserved");
      const candidate = snapshot(), existing = candidate.sources.find(item => item.id === source.id);
      if (!existing) candidate.sources.push(source);
      else if (source.recipe && JSON.stringify(existing.recipe) !== JSON.stringify(source.recipe)) throw new Error("This audio already exists with a different recipe; existing sources preserved");
      const checked = M.replaceTrackSource(candidate, target.track, target.source.id, source.id, caps);
      await audio().loadSources(checked.sources, buffer ? new Map([[source.id, buffer]]) : undefined);
      sources = checked.sources; trackSources = checked.trackSources;
      bridge.replaceScene(checked.scene); renderSources();
    }
    if (window.NativeControls) native = window.NativeControls.attach({
      context: nativeContext,
      buffer: id => audio().entries.get(id).buffer,
      decode: bytes => audio().context.decodeAudioData(bytes.slice().buffer),
      apply: replace,
      original: async () => {
        const target = nativeContext();
        if (target.source && target.parent && target.source.id !== target.parent.id) await replace(target, target.parent);
      },
    });
    return {
      report,
      cancelNative: invalidateNative,
      trackLabel(index) { const source = sources.find(item => item.id === trackSources[index]); return source ? source.name : P.TRACKS[index]; },
      cell(trackIndex, base) {
        const sourceId = trackSources[trackIndex];
        if (sourceId) return Object.assign({}, base, { note: 60, sampleId: sourceId,
          slice: trackIndex === track() ? selectedSlice : 0 });
        return base;
      },
      selectTrack(index) { $("sample-track").value = String(index); selectedSlice = 0; renderSources(); },
    };
  } };
})();
