# Alchemical Synthesizer (Brahma Meta-Rack) — root-to-leaf entry points.
#
#   make smoke     run the user smoke test (structure, extension, validator, web)
#   make dist      build distributable artifacts into dist/
#   make serve     install web deps and launch the Visual Cortex (port 3000)
#   make validate  validate an audio specimen:  make validate FILE=path/to.wav
#   make install   symlink SC .sc classes into SC Extensions + recompile
#   make start     layered start (SC -> Web -> Pd; --no-sc/--no-web/--no-pd)
#   make clean     remove build output and installed web deps
#
#   -- The Forge: sample -> track pipeline --
#   make stations  list the AETHER source registry (where Brahma listens)
#   make tune      listen: capture free/web audio:  make tune STATION=somafm-dronezone [SECS=30] | make tune URL=https://... [LICENSE=cc0]
#   make rip       rip a song into stems:        make rip SONG=song.mp3 [NAME=song]
#   make forge     recombine stolen stems:        make forge NAME=heist DRUMS=a/drums.wav MELODY=b/other.wav
#   make render    Brahma re-expresses a WAV:      make render SONG=in.wav OUT=out.wav [DUR=12]
#   make track     stems -> re-expressed track:    make track NAME=heist DRUMS=a/drums.wav MELODY=b/other.wav OUT=out/heist.wav [DUR=12]
#   make stemtrack per-stem modular render:         make stemtrack NAME=heist DRUMS=a/drums.wav MELODY=b/other.wav OUT=out/heist.wav [MAP=drums=ossuary,other=janiform] [DUR=12]
#   make videotrack track -> matching visual clip:  make videotrack TRACK=out/heist.wav [OUT=out/heist.mp4] [FPS=30] [WIDTH=1080] [HEIGHT=1080] [SUBSTRATE=sound]
#   make package   track -> social-ready bundle:     make package TRACK=out/heist.wav [TITLE="Heist"] [LINK=https://...] [SUBSTRATE=sound]
#   make broadcast AETHER live radio (segmented-NRT -> live HLS):  make broadcast [SOURCE=out/tuned/x.wav] [SEGMENTS=0] [SECONDS=..] [SEED=1] [PERIOD=12]
#   make rebroadcast push the stream to YouTube/Twitch (RTMP lure):  make rebroadcast TARGET=youtube (key via env RTMP_KEY) | make rebroadcast DRYRUN=out/preview.flv
#   make submit    Ω feed the organism (a creature eats it live):  make submit URL=https://host/stream [LICENSE=cc0]  (also POST /submit on the live host; add OUROBOROS=1 to `make broadcast`)
#   make demucs    install TRUE separation (htdemucs) for higher-quality rips
#   make video     install headless video export (puppeteer) for videotrack

.PHONY: help smoke dist serve validate clean install start stations tune rip forge render track stemtrack videotrack package broadcast rebroadcast submit demucs video

help:
	@grep -E '^#   make ' Makefile | sed 's/^#   /  /'

smoke:
	bash tools/smoke.sh

dist:
	bash tools/build_release.sh

serve:
	cd brahma/web && npm install && npm start

validate:
	@test -n "$(FILE)" || { echo "usage: make validate FILE=path/to.wav"; exit 1; }
	python3 forge/validate_audio.py "$(FILE)"

clean:
	rm -rf dist brahma/web/node_modules

# install: symlink the six Brahma .sc classes into SC Extensions and recompile.
install:
	bash tools/install-brahma.sh

# start: layered start of the rack (SC engine -> Visual Cortex -> Pure Data).
#   make start                # all tiers
#   make start --no-pd        # skip Pure Data
#   make start PORT=4000      # custom web port
start:
	bash tools/start-brahma.sh $(if $(PORT),--port $(PORT),)

# ---- The Forge: sample -> track pipeline ----

# stations / tune: the "listen" mouth of the Forge (AETHER). `make stations`
# lists the license-tagged source registry; `make tune` captures a slice of a
# free/streaming web source into a Forge-ready WAV (+ a provenance sidecar).
# Rights posture is human-gated — captures are license-tagged, not cleared.
stations:
	python3 aether/tools/tune.py --list

tune:
	@test -n "$(STATION)" || test -n "$(URL)" || \
		{ echo "usage: make tune STATION=somafm-dronezone [SECS=30] [OUT=out/tuned/x.wav]"; \
		  echo "   or: make tune URL=https://host/stream [LICENSE=cc0] [SECS=30] [OUT=...]"; exit 1; }
	python3 aether/tools/tune.py $(if $(STATION),--station $(STATION),) $(if $(URL),--url "$(URL)",) \
		$(if $(SECS),--secs $(SECS),) $(if $(LICENSE),--license $(LICENSE),) $(if $(OUT),--out "$(OUT)",)

rip:
	@test -n "$(SONG)" || { echo "usage: make rip SONG=song.mp3 [NAME=song]"; exit 1; }
	python3 forge/rip.py "$(SONG)" $(if $(NAME),--name $(NAME),)

forge:
	@test -n "$(NAME)" && test -n "$(DRUMS)" && test -n "$(MELODY)" || \
		{ echo "usage: make forge NAME=x DRUMS=a/drums.wav MELODY=b/other.wav [BASS=..] [VOCALS=..]"; exit 1; }
	bash forge/forge.sh --name $(NAME) --drums "$(DRUMS)" --melody "$(MELODY)" \
		$(if $(BASS),--bass "$(BASS)",) $(if $(VOCALS),--vocals "$(VOCALS)",) --mix

render:
	@test -n "$(SONG)" && test -n "$(OUT)" || { echo "usage: make render SONG=in.wav OUT=out.wav [DUR=12]"; exit 1; }
	bash forge/bounce.sh "$(SONG)" "$(OUT)" $(DUR)

track:
	@test -n "$(NAME)" && test -n "$(DRUMS)" && test -n "$(MELODY)" && test -n "$(OUT)" || \
		{ echo "usage: make track NAME=x DRUMS=a/drums.wav MELODY=b/other.wav OUT=out/x.wav [DUR=12]"; exit 1; }
	bash forge/forge.sh --name $(NAME) --drums "$(DRUMS)" --melody "$(MELODY)" --mix
	bash forge/bounce.sh forge/recipes/$(NAME)/premix.wav "$(OUT)" $(DUR)

# stemtrack: like track, but render EACH stem through its own creature-voice and
# sum under a master limiter (drums->ossuary, bass->mnemosyne, vocals->chrysalid,
# melody->prima). No premix — the modular path. --map/DUR are optional.
stemtrack:
	@test -n "$(NAME)" && test -n "$(DRUMS)" && test -n "$(MELODY)" && test -n "$(OUT)" || \
		{ echo "usage: make stemtrack NAME=x DRUMS=a/drums.wav MELODY=b/other.wav OUT=out/x.wav [BASS=..] [VOCALS=..] [MAP=drums=ossuary] [DUR=12]"; exit 1; }
	bash forge/forge.sh --name $(NAME) --drums "$(DRUMS)" --melody "$(MELODY)" \
		$(if $(BASS),--bass "$(BASS)",) $(if $(VOCALS),--vocals "$(VOCALS)",)
	python3 forge/stemforge.py $(NAME) --out "$(OUT)" $(if $(DUR),--dur $(DUR),) $(if $(MAP),--map $(MAP),)

demucs:
	bash forge/setup-demucs.sh

# videotrack: a rendered track -> a matching audio-reactive video. Analyzes the
# audio into a per-frame envelope, drives the Etz Chaim cosmos headlessly, and
# muxes frames + audio into a post-ready mp4. Needs `make video` first.
videotrack:
	@test -n "$(TRACK)" || { echo "usage: make videotrack TRACK=out/heist.wav [OUT=out/heist.mp4] [FPS=30] [WIDTH=1080] [HEIGHT=1080] [SUBSTRATE=sound]"; exit 1; }
	bash forge/videotrack.sh --track "$(TRACK)" \
		$(if $(OUT),--out "$(OUT)",) $(if $(FPS),--fps $(FPS),) \
		$(if $(WIDTH),--width $(WIDTH),) $(if $(HEIGHT),--height $(HEIGHT),) \
		$(if $(SUBSTRATE),--substrate $(SUBSTRATE),)

video:
	bash forge/setup-video.sh

# package: a rendered track -> a social-ready bundle (video + cover + caption) in
# out/pkg/<base>/. Burns a "made with Brahma" mark into the clip and picks the
# peak-energy frame as the cover. Set BRAHMA_LINK to bake your funnel URL in.
package:
	@test -n "$(TRACK)" || { echo "usage: make package TRACK=out/heist.wav [TITLE=\"Heist\"] [LINK=https://...] [SUBSTRATE=sound]"; exit 1; }
	bash forge/package.sh --track "$(TRACK)" \
		$(if $(TITLE),--title "$(TITLE)",) $(if $(LINK),--link "$(LINK)",) \
		$(if $(SUBSTRATE),--substrate $(SUBSTRATE),) $(if $(FPS),--fps $(FPS),)

# broadcast: AETHER's living radio. The Cell-Cycle organism (tools/cellcycle.py)
# conducts a continuous, evolving performance -> segmented render (SuperCollider
# NRT when present; folded donor or a genome-reactive tone otherwise) -> a LIVE
# rolling HLS stream in out/live (served at /live; watch it at /aether). Fold a
# tune capture in with SOURCE=. SEGMENTS=0 (default) streams forever.
broadcast:
	bash aether/tools/broadcast.sh \
		$(if $(SOURCE),--source "$(SOURCE)",) $(if $(SEGMENTS),--segments $(SEGMENTS),) \
		$(if $(SECONDS),--seconds $(SECONDS),) $(if $(SEED),--seed $(SEED),) \
		$(if $(PERIOD),--period $(PERIOD),) $(if $(OUT),--out "$(OUT)",) \
		$(if $(OUROBOROS),--ouroboros,)

# submit: the Ω "feed the organism" enqueue — a stream URL a creature eats live.
# (Also exposed over HTTP as POST /submit on the live host.) URL required.
submit:
	@test -n "$(URL)" || { echo "usage: make submit URL=https://host/stream [LICENSE=cc0] [OUT=out/live]"; exit 1; }
	python3 aether/tools/ingest_queue.py add --url "$(URL)" $(if $(LICENSE),--license $(LICENSE),) \
		--dir "$(if $(OUT),$(OUT),out/live)/queue"

# rebroadcast: the "Reach" lure — push the sovereign stream to YouTube/Twitch over
# RTMP (ffmpeg synthesizes a visualizer video from the audio). The stream key is
# an organ-owned credential (env RTMP_KEY, never recited). DRYRUN= renders a local
# preview .flv with no push and no key.
rebroadcast:
	bash aether/tools/rebroadcast.sh $(if $(TARGET),--target $(TARGET),) $(if $(URL),--url "$(URL)",) \
		$(if $(INPUT),--input "$(INPUT)",) $(if $(MODE),--mode $(MODE),) $(if $(DRYRUN),--dry-run "$(DRYRUN)",)
