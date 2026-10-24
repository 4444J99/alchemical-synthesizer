# ============================================================================
#  AETHER 24/7 sovereign radio — the generator + stream host as a container.
# ----------------------------------------------------------------------------
#  AETHER plan §5.3. Runs the METABOLISM organism (tools/cellcycle.py) driving
#  tools/broadcast.sh -> a LIVE HLS stream, served by the dependency-free
#  deploy/aether/serve.js (node builtins only — no npm install, no native
#  builds). No SuperCollider in this image: the broadcast's graceful fallback
#  tiers (folded donor / genome-reactive tone) keep the stream live without it,
#  so the sovereign host is small and reliable. SC re-expression is a heavier
#  image variant for later.
#
#  BUILD CONTEXT = the repository root (COPY paths are repo-relative):
#     docker build -f aether/deploy/Dockerfile -t aether-radio .
# ============================================================================
FROM node:20-bookworm-slim

# ffmpeg (transport) + python3 (organism + hls_append). bash for the entrypoint.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg python3 bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# The generator toolchain, the theatron player (static), and the runtime.
COPY aether/tools/ /app/tools/
# broadcast.sh reuses two Forge-lane tools (Aether -> Forge dependency, see
# ORGANS.md): aether/tools/tune.py captures a queued submission,
# forge/bounce.sh is the NRT render tier (SC-gated, no-op in this SC-less image
# but kept for parity).
COPY aether/tools/tune.py forge/bounce.sh /app/forge/
COPY aether/web/listener/ /app/player/
COPY deploy/aether/serve.js deploy/aether/entrypoint.sh /app/

RUN mkdir -p /live \
 && chmod +x /app/entrypoint.sh /app/tools/broadcast.sh /app/tools/*.py 2>/dev/null || true

ENV PORT=8080 \
    AETHER_LIVE_DIR=/live \
    AETHER_STATIC_DIR=/app/player \
    AETHER_SECONDS=12 \
    AETHER_LIST_SIZE=6
EXPOSE 8080
VOLUME ["/live"]

# Liveness: the stream server answers. (node is already present; no curl needed.)
HEALTHCHECK --interval=30s --timeout=4s --start-period=10s \
  CMD node -e "require('http').get('http://localhost:'+(process.env.PORT||8080)+'/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

ENTRYPOINT ["/app/entrypoint.sh"]
