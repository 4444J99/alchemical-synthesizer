/* Glass is an interpretation of retained matter and measured track audio. */
(function () {
  "use strict";
  const M = window.MaterialModel, library = M.payload.library;
  const $ = id => document.getElementById(id);
  window.MaterialControls = { attach(bridge) {
    const inputs = new Map(), cards = [];
    for (const [id, spec] of Object.entries(library.materials)) {
      const label = document.createElement("label"), input = document.createElement("input");
      label.textContent = spec.name + " %"; input.type = "number"; input.min = 0; input.max = 100;
      input.step = 1; input.value = id === "water" ? 100 : 0; input.dataset.material = id;
      input.setAttribute("aria-label", spec.name + " percentage"); label.appendChild(input);
      $("material-composition").appendChild(label); inputs.set(id, input);
      input.addEventListener("input", changed);
    }
    function value() {
      if (!$("material-enable").checked) return null;
      const composition = [];
      for (const [id, input] of inputs) {
        if (!input.checkValidity() || input.value === "") throw new Error("Material percentages must be between 0 and 100");
        if (Number(input.value) > 0) composition.push({ id, fraction: Number(input.value) / 100 });
      }
      return M.validate({ schema: M.SCHEMA, modelVersion: library.version,
        phase: $("material-phase").value, amount: Number($("material-amount").value), composition });
    }
    function changed() { bridge.changed(); refresh(); }
    for (const id of ["material-enable", "material-phase"]) $(id).addEventListener("change", changed);
    $("material-amount").addEventListener("input", changed);
    function restore(state) {
      $("material-enable").checked = !!state;
      $("material-phase").value = state ? state.phase : "liquid";
      $("material-amount").value = state ? state.amount : 1;
      for (const [id, input] of inputs) input.value = state ?
        Math.round((state.composition.find(component => component.id === id)?.fraction || 0) * 10000) / 100 : id === "water" ? 100 : 0;
      refresh();
    }
    function refresh() {
      const module = bridge.module(), support = M.describe(module), source = bridge.context().source;
      $("material-enable").disabled = !support.supported;
      const disabled = !support.supported || !$("material-enable").checked;
      for (const input of [...inputs.values(), $("material-phase"), $("material-amount")]) input.disabled = disabled;
      $("native-claim").textContent = support.claim;
      $("material-error").textContent = "";
      try {
        const state = value(), base = bridge.params();
        const resolved = state ? M.resolve(module, base, state) : null;
        $("material-effective").textContent = resolved ? Object.entries(resolved.params).map(([key, next]) =>
          key + ": " + M.baseControls(module, base)[key] + " → " + next).join("\n") : "Native controls unchanged. Enable a mapped material to shape this organism.";
        $("material-amount-value").textContent = Math.round(Number($("material-amount").value) * 100) + "%";
      } catch (error) { $("material-error").textContent = error.message; $("material-effective").textContent = "Correct the mixture before rendering or saving."; }
      const applied = source && source.recipe;
      $("material-applied").textContent = applied ? "Playing source: " + applied.module +
        (applied.material ? " · " + applied.material.phase + " · " + applied.material.composition.map(c =>
          library.materials[c.id].name + " " + Math.round(c.fraction * 100) + "%").join(" + ") : " · native controls") : "Playing source: original audio or synth voice.";
      $("material-applied").textContent += " Editor changes are a draft until Render and use completes.";
      updateCards();
    }
    function valid() { try { value(); bridge.params(); return true; } catch (_) { return false; } }
    const tracks = bridge.tracks();
    tracks.forEach((_, index) => {
      const button = document.createElement("button"), canvas = document.createElement("canvas");
      button.type = "button"; button.className = "vessel-card"; button.dataset.track = index;
      canvas.width = 180; canvas.height = 100; canvas.setAttribute("aria-hidden", "true");
      const name = document.createElement("strong"), caption = document.createElement("small");
      button.append(canvas, name, caption); button.addEventListener("click", () => bridge.selectTrack(index));
      $("material-vessels").appendChild(button); cards.push({ button, canvas, name, caption });
    });
    function updateCards() {
      bridge.tracks().forEach((track, index) => {
        const card = cards[index], recipe = track.source && track.source.recipe;
        const material = recipe && recipe.material;
        card.button.setAttribute("aria-pressed", String(index === bridge.context().track));
        card.button.dataset.phase = material ? material.phase : "empty";
        card.name.textContent = track.name + " · " + (recipe ? recipe.module.replaceAll("_", " ") : "original");
        card.caption.textContent = material ? material.phase + " · " + material.composition.map(c => library.materials[c.id].name).join(" + ") : "Unprocessed matter";
        if (track.vessel) card.caption.textContent += " · draft " + track.vessel.module.replaceAll("_", " ");
      });
    }
    function frame() {
      if (!document.hidden) bridge.tracks().forEach((track, index) => {
        const { canvas } = cards[index], c = canvas.getContext("2d"), w = canvas.width, h = canvas.height;
        const recipe = track.source && track.source.recipe, state = recipe && recipe.material;
        const phase = state ? state.phase : "empty", level = bridge.level(index), energy = Math.min(1, level.rms * 5);
        const color = state ? library.materials[state.composition[0].id].color : "#87a5b9";
        c.clearRect(0, 0, w, h); c.strokeStyle = color; c.fillStyle = color;
        c.globalAlpha = .14 + energy * .4;
        if (phase === "solid") {
          for (let x = 12; x < w - 15; x += 26) {
            const y = 40 + (x % 3) * 6 - energy * 12;
            c.beginPath(); c.moveTo(x, h - 5); c.lineTo(x - 5, y + 15); c.lineTo(x + 9, y);
            c.lineTo(x + 22, y + 15); c.lineTo(x + 24, h - 5); c.closePath(); c.fill(); c.stroke();
          }
        } else if (phase === "gas") {
          for (let i = 0; i < 35; i++) {
            const wave = level.wave ? level.wave[(i * 13) % level.wave.length] : 0;
            c.beginPath(); c.arc(12 + (i * 31 % 150), 12 + (i * 17 % 75) + wave * 20,
              1.5 + energy * 3, 0, Math.PI * 2); c.fill();
          }
        } else {
          c.beginPath(); c.moveTo(0, h);
          for (let x = 0; x <= w; x++) {
            const wave = level.wave ? level.wave[Math.floor(x / w * (level.wave.length - 1))] : 0;
            c.lineTo(x, (phase === "liquid" ? 48 : 76) - wave * 55);
          }
          c.lineTo(w, h); c.closePath(); c.fill();
        }
        c.globalAlpha = .8; c.lineWidth = 1; c.beginPath();
        for (let x = 0; x < w; x++) {
          const wave = level.wave ? level.wave[Math.floor(x / w * (level.wave.length - 1))] : 0;
          if (x) c.lineTo(x, 49 - wave * 65); else c.moveTo(x, 49 - wave * 65);
        }
        c.stroke(); c.globalAlpha = 1;
      });
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
    return { value, restore, refresh, valid };
  } };
})();
