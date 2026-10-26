/* Native DSP is rendered locally, then applied to future notes on this track. */
(function () {
  "use strict";
  const M = window.SampleProject, A = window.SampleAudio;
  const $ = id => document.getElementById(id);
  window.NativeControls = { attach(bridge) {
    let modules = [], revision = 0, pending = null, connected = false;
    let matter = null;
    const report = (text, error) => { $("native-status").textContent = text; $("native-status").className = error ? "error" : ""; };
    async function json(url, options) {
      const response = await fetch(url, options), result = await response.json();
      if (!response.ok) throw new Error(result.error || "Native request failed");
      return result;
    }
    function controls(values) {
      const module = modules.find(item => item.name === $("native-module").value);
      $("native-params").replaceChildren();
      for (const [key, spec] of Object.entries(module && module.controls || {})) {
        const label = document.createElement("label"), input = document.createElement("input");
        label.textContent = spec[0] + " "; input.type = "number"; input.min = spec[1]; input.max = spec[2];
        input.step = spec[3]; input.required = true; input.value = values && values[key] !== undefined ? values[key] : spec[4]; input.dataset.param = key;
        input.addEventListener("input", changed);
        label.appendChild(input); $("native-params").appendChild(label);
      }
      $("native-role").textContent = module ? module.role.replaceAll("_", " ") +
        (Object.keys(module.controls || {}).length ? "" : " - native patch defaults") : "";
    }
    function refresh(restoreRecipe) {
      const context = bridge.context(), recipe = context.source && context.source.recipe;
      const saved = context.vessel || (recipe && { module: recipe.module, params: recipe.baseParams || recipe.params, material: recipe.material || null });
      if (restoreRecipe && saved && modules.some(item => item.name === saved.module)) {
        $("native-module").value = saved.module; controls(saved.params); if (matter) matter.restore(saved.material);
      } else if (restoreRecipe && !saved) { controls(); if (matter) matter.restore(null); }
      if (matter) matter.refresh();
      $("native-render").disabled = !connected || !!pending || !context.source || (matter && !matter.valid());
      $("native-original").disabled = !recipe || !!pending;
      $("native-audition-original").disabled = $("native-audition-current").disabled = !context.source;
    }
    function params() {
      const values = {};
      $("native-params").querySelectorAll("input").forEach(input => {
        if (input.value === "" || !input.checkValidity()) throw new Error("Native control is outside its range");
        values[input.dataset.param] = Number(input.value);
      });
      return values;
    }
    function settings() { return M.vessel({ module: $("native-module").value, params: params(), material: matter ? matter.value() : null }); }
    function changed() {
      cancel();
      try { bridge.setVessel(settings()); } catch (error) { report(error.message, true); }
      refresh();
    }
    async function connect() {
      try {
        const fragment = new URLSearchParams(location.hash.slice(1)), token = fragment.get("t"); // allow-secret: transient launch fragment, no embedded credential
        if (token) {
          history.replaceState(null, "", location.pathname + location.search);
          await json("/api/auth/exchange", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token }) });
        }
        const auth = await json("/api/auth/status");
        if (auth.role !== "human") throw new Error("Open the instrument launch link printed by the local server, then connect here.");
        const catalogue = await json("/api/instrument/native/catalogue");
        modules = catalogue.modules;
        const select = $("native-module"); select.replaceChildren();
        modules.forEach(item => {
          const unavailable = item.role === "infrastructure" || !(item.audio_outputs.length || item.control_outputs.length);
          const option = new Option(item.name + (unavailable ? " - requires its own patch" : ""), item.name);
          option.disabled = unavailable; select.add(option);
        });
        select.value = "chrysalid_siren_stereo"; connected = true; controls(); refresh(true);
        report("Native engine connected. Render a new sound, then hear it in this track.");
      } catch (error) { connected = false; report(error.message, true); refresh(); }
    }
    function cancel() {
      revision++;
      const job = pending; pending = null;
      if (job && job.id) json("/api/instrument/native/jobs/" + encodeURIComponent(job.id), { method: "DELETE" }).catch(() => {});
      if (job) report("Cancelled native render. Current sound preserved.");
      refresh();
    }
    async function render() {
      if (pending || !connected) return;
      const target = bridge.context();
      if (!target.source || !target.parent) return;
      const generation = ++revision, request = { id: null }; pending = request; refresh();
      const current = () => generation === revision && bridge.context().revision === target.revision &&
        bridge.context().track === target.track && bridge.context().source && bridge.context().source.id === target.source.id;
      try {
        if (target.parent.duration < 1 || target.parent.duration > 30) throw new Error("Native rendering uses sounds of 1-30 seconds. Load a short excerpt or an audition WAV.");
        report("Preparing native sound...");
        const selected = settings(), baseParams = selected.params, material = selected.material;
        const resolved = material ? window.MaterialModel.resolve(selected.module, baseParams, material) : null;
        const context = new OfflineAudioContext(2, Math.round(target.parent.duration * 44100), 44100);
        const voice = context.createBufferSource(); voice.buffer = bridge.buffer(target.parent.id);
        voice.connect(context.destination); voice.start(0);
        const normalized = new Uint8Array(A.wavBytes(await context.startRendering()));
        const input = await M.createSource(normalized, { name: "Native input.wav", mime: "audio/wav",
          duration: target.parent.duration, sampleRate: 44100, channels: 2 });
        if (!current()) return;
        const module = $("native-module").value;
        let job = await json("/api/instrument/native/jobs", { method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ module, params: baseParams, material, audio: { data: input.data, sha256: input.sha256 } }) });
        request.id = job.id;
        if (!current()) { await json("/api/instrument/native/jobs/" + encodeURIComponent(job.id), { method: "DELETE" }); return; }
        report("Rendering native sound... The current loop keeps playing.");
        const deadline = Date.now() + 150000;
        while (job.state === "running") {
          await new Promise(resolve => setTimeout(resolve, 250));
          if (!current()) return;
          if (Date.now() > deadline) throw new Error("Native render deadline reached");
          job = await json("/api/instrument/native/jobs/" + encodeURIComponent(job.id));
        }
        if (job.state !== "completed") throw new Error(job.error || "Native render did not complete");
        if (job.sourceSha256 !== input.sha256) throw new Error("Native source receipt mismatch");
        if (job.module !== module || (material && (JSON.stringify(job.material) !== JSON.stringify(resolved.material) ||
            JSON.stringify(job.params) !== JSON.stringify(resolved.params) || job.result.modelSha256 !== resolved.modelSha256))) throw new Error("Native material receipt mismatch");
        const response = await fetch("/api/instrument/native/jobs/" + encodeURIComponent(job.id) + "/audio");
        if (!response.ok) throw new Error("Native audio is unavailable");
        const bytes = new Uint8Array(await response.arrayBuffer());
        if (await M.digest(bytes) !== job.result.sha256) throw new Error("Native output integrity check failed");
        const buffer = await bridge.decode(bytes);
        const source = await M.createSource(bytes, { name: target.parent.name + " / " + module,
          mime: "audio/wav", duration: buffer.duration, sampleRate: buffer.sampleRate, channels: buffer.numberOfChannels });
        source.slices = target.source.slices.map(slice => ({ ...slice }));
        source.recipe = { schema: "brahma.native-recipe.v1", parentId: target.parent.id, module, params: job.params || baseParams,
          inputSha256: input.sha256, definitionSha256: job.result.definitionSha256, rackSha256: job.result.rackSha256 };
        if (material) Object.assign(source.recipe, { material: resolved.material, baseParams, modelSha256: resolved.modelSha256 });
        if (!current()) return;
        if (source.id === target.parent.id) { report("Native result matches the original audio. Current sound preserved."); return; }
        await bridge.apply(target, source, buffer);
        if (generation === revision) report("Applied " + module + ". Original and recipe retained; future notes use this sound.");
      } catch (error) {
        if (generation === revision) {
          if (request.id) json("/api/instrument/native/jobs/" + encodeURIComponent(request.id), { method: "DELETE" }).catch(() => {});
          report(error.message, true);
        }
      } finally { if (generation === revision) { pending = null; refresh(); } }
    }
    $("native-connect").addEventListener("click", connect);
    $("native-module").addEventListener("change", () => {
      cancel(); controls();
      if (matter && !window.MaterialModel.describe($("native-module").value).supported) matter.restore(null);
      changed();
    });
    $("native-render").addEventListener("click", render);
    $("native-original").addEventListener("click", async () => {
      cancel();
      try { await bridge.original(); report("Original restored for future notes."); } catch (error) { report(error.message, true); }
    });
    $("native-cancel").addEventListener("click", cancel);
    for (const [id, original] of [["native-audition-original", true], ["native-audition-current", false]]) {
      $(id).addEventListener("click", async () => {
        try { await bridge.audition(original); } catch (error) { report(error.message, true); }
      });
    }
    if (window.MaterialControls) matter = window.MaterialControls.attach({
      context: bridge.context, tracks: bridge.tracks, selectTrack: bridge.selectTrack, level: bridge.level,
      module: () => $("native-module").value, params, changed,
    });
    if (matter) matter.refresh();
    connect();
    return { cancel, refresh, validate() { if (connected) settings(); } };
  } };
})();
