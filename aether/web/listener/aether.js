// ============================================================================
//  aether.js — the theatron player + living-organism overlay for AETHER.
// ----------------------------------------------------------------------------
//  Grafts etceter4's HLS.js player idiom (converge, don't rebuild — see
//  docs/AETHER-BROADCAST-PLAN.md §3) onto Brahma's broadcast. It:
//    * attaches the LIVE HLS stream (tools/broadcast.sh -> /live/stream.m3u8)
//      via HLS.js, or Safari's native HLS when Hls.js is unsupported;
//    * polls /live/telemetry.json and renders the organism's PROVISIONAL inner
//      life (phase, active creature, coherence/entropy, the metabolic arc,
//      lineage) — always labeled provisional, per docs/logos/pragma.md.
//
//  Pure browser JS, no build step (served static by brahma/web/server.js, and
//  CF-Pages/Vercel-deployable as-is). Degrades gracefully before the organism
//  wakes: shows "offline / awaiting the organism" rather than erroring.
// ============================================================================
(function () {
    "use strict";

    // Where the broadcast's live output is served. server.js maps /live -> the
    // broadcast out dir; a static host maps it to the uploaded segments dir.
    var STREAM = "/live/stream.m3u8";
    var TELEMETRY = "/live/telemetry.json";
    var POLL_MS = 2000;
    var PHASES = ["readable", "cluster", "dispersal"];

    var $ = function (id) { return document.getElementById(id); };
    var audio = $("audio");
    var lastSeg = -1, offlineStrikes = 0;

    // ---- 1. Attach the live HLS stream ----------------------------------
    function attach() {
        if (window.Hls && window.Hls.isSupported()) {
            var hls = new window.Hls({
                liveSyncDurationCount: 3,   // stay near the live edge
                lowLatencyMode: false,
                enableWorker: true,
            });
            hls.loadSource(STREAM);
            hls.attachMedia(audio);
            hls.on(window.Hls.Events.MANIFEST_PARSED, function () {
                $("hint").textContent = "Stream ready — press play.";
            });
            hls.on(window.Hls.Events.ERROR, function (evt, data) {
                if (data && data.fatal) {
                    // A live stream may briefly 404 before the first segment;
                    // recover rather than dying.
                    if (data.type === window.Hls.ErrorTypes.NETWORK_ERROR) {
                        setTimeout(function () { hls.startLoad(); }, 1500);
                    } else if (data.type === window.Hls.ErrorTypes.MEDIA_ERROR) {
                        hls.recoverMediaError();
                    }
                }
            });
        } else if (audio.canPlayType("application/vnd.apple.mpegurl")) {
            // Safari / iOS: native HLS.
            audio.src = STREAM;
            $("hint").textContent = "Stream ready (native HLS) — press play.";
        } else {
            $("hint").textContent = "This browser can't play HLS. Try Safari, or a Chromium/Firefox build.";
        }
    }

    // ---- 2. Render the organism's provisional inner life -----------------
    function pct(v) { return Math.round((Number(v) || 0) * 100); }

    function setMeter(name, v) {
        var bar = $("bar-" + name), val = $("val-" + name);
        if (bar) bar.style.width = pct(v) + "%";
        if (val) val.textContent = pct(v) + "%";
    }

    function renderArc(period, segInCycle, phase) {
        var arc = $("arc");
        if (arc.childElementCount !== period) {
            arc.innerHTML = "";
            for (var k = 0; k < period; k++) {
                var seg = document.createElement("span");
                var ph = PHASES[Math.min(Math.floor((k / period) * 3), 2)];
                seg.className = "seg " + ph;
                arc.appendChild(seg);
            }
        }
        for (var j = 0; j < arc.childElementCount; j++) {
            arc.children[j].classList.toggle("on", j === segInCycle);
        }
    }

    function render(t) {
        var n = t && t.now;
        if (!n) return;
        setLive(true);

        $("phase").textContent = n.phase.toUpperCase();
        $("phase").className = "badge phase-" + n.phase;
        $("creature").textContent = n.creature.replace(/-/g, " ");
        $("epoch").textContent = "epoch " + n.epoch + " · segment " + n.segment
            + (n.reborn ? " · ⟲ reborn" : "");

        setMeter("coherence", n.coherence);
        setMeter("fidelity", n.fidelity);
        setMeter("entropy", n.entropy);
        setMeter("drift", n.drift);

        // The metabolic arc: infer the cycle period from the segment/epoch.
        var period = (n.segment && n.epoch >= 0)
            ? Math.max(3, Math.round((n.segment) / Math.max(1, n.epoch + (n.phase_pos || 0))) || 12)
            : 12;
        if (!isFinite(period) || period < 3 || period > 64) period = 12;
        renderArc(period, n.segment % period, n.phase);

        if (n.render_tier) {
            var label = { nrt: "NRT re-expression (SuperCollider)",
                          donor: "donor passthrough", tone: "self-generated tone" }[n.render_tier] || n.render_tier;
            $("tier").textContent = "render tier: " + label;
        }

        // Lineage: the recent stream of segments (a lineage, not a loop).
        if (t.recent && t.recent.length) {
            var chips = t.recent.slice(-8).map(function (r) {
                return r.creature.split("-")[0] + "·" + r.phase[0];
            });
            $("lineage").innerHTML = "<b>lineage</b> → " + chips.join(" · ")
                + "  (" + (t.count || t.recent.length) + " segments this life)";
        }
        lastSeg = n.segment;
    }

    function setLive(on) {
        var flag = $("liveflag"), text = $("livetext");
        flag.className = "live" + (on ? "" : " off");
        text.textContent = on ? "on air" : "offline";
    }

    // ---- 3. Poll telemetry ----------------------------------------------
    function poll() {
        fetch(TELEMETRY, { cache: "no-store" })
            .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
            .then(function (t) { offlineStrikes = 0; render(t); })
            .catch(function () {
                // Before the first segment (or between runs) telemetry 404s.
                if (++offlineStrikes >= 2) setLive(false);
            });
    }

    // ---- 4. Ω · Ouroboros: feed the organism + render the lineage ------
    var LINEAGE = STREAM_BASE + "/lineage.json";

    function initOuroboros() {
        var form = document.getElementById("ob-form");
        if (!form) return;
        form.addEventListener("submit", function (e) {
            e.preventDefault();
            var url = document.getElementById("ob-url").value.trim();
            var lic = document.getElementById("ob-license").value;
            var msg = document.getElementById("ob-msg");
            if (!/^https?:\/\//i.test(url)) { msg.textContent = "Enter a http(s) stream URL."; return; }
            msg.textContent = "feeding…";
            fetch("/submit", {
                method: "POST", headers: { "content-type": "application/json" },
                body: JSON.stringify({ url: url, license: lic }),
            })
                .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
                .then(function (res) {
                    msg.textContent = res.ok
                        ? "queued — a creature will eat it live. (" + (res.j.id || "queued") + ")"
                        : "couldn't queue: " + (res.j.error || "unavailable");
                    if (res.ok) form.reset();
                })
                .catch(function () { msg.textContent = "submission endpoint unreachable (needs the live host)."; });
        });
    }

    function pollLineage() {
        var box = document.getElementById("chain");
        if (!box) return;
        fetch(LINEAGE, { cache: "no-store" })
            .then(function (r) { if (!r.ok) throw 0; return r.json(); })
            .then(function (d) {
                var es = (d && d.entries) || [];
                if (!es.length) { box.innerHTML = ""; return; }
                var chain = es.slice(-10).map(function (e) {
                    var self = e.source === "ouroboros:self";
                    var src = self ? "∞ self" : (e.source || "").replace(/^https?:\/\//, "").slice(0, 28);
                    return '<span class="' + (self ? "self" : "lk") + '">' + e.creature.split("-")[0] + " ⟵ " + src + "</span>";
                });
                box.innerHTML = "<b>lineage</b> (" + es.length + " absorbed) — " + chain.join(" · ");
            })
            .catch(function () { /* no lineage yet */ });
    }

    attach();
    initOuroboros();
    poll();
    pollLineage();
    setInterval(poll, POLL_MS);
    setInterval(pollLineage, POLL_MS * 2);
})();
