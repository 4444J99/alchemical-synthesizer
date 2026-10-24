// ============================================================================
//  worker.mjs — the Cloudflare Worker that fronts the AETHER container.
// ----------------------------------------------------------------------------
//  AETHER plan §5.3, the D3 "24/7 sovereign" host. Cloudflare Containers are
//  driven by a Worker + a Durable Object that owns the container instance
//  (see @cloudflare/containers). This Worker:
//    * serves durable HLS segments from R2 when present (survives container
//      recycles + gets CDN edge caching) — "R2 for segments";
//    * otherwise proxies to the running container (the live generator + serve.js).
//
//  Bindings (wrangler.toml): AETHER_CONTAINER (the DO/container) and SEGMENTS
//  (the R2 bucket). Deploying this is the human-gated atom L-MEDIA-ARK-HOST
//  ($5/mo Workers Paid) — see README.md.
// ============================================================================
import { Container, getContainer } from "@cloudflare/containers";

export class AetherContainer extends Container {
  // The container listens on 8080 (serve.js). A radio should stay awake; set a
  // long idle so CF doesn't sleep it between listeners.
  defaultPort = 8080;
  sleepAfter = "6h";
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1. Durable segment path: serve /live/* from R2 if the object exists.
    if (url.pathname.startsWith("/live/") && env.SEGMENTS) {
      const key = url.pathname.slice("/live/".length);
      if (key) {
        const obj = await env.SEGMENTS.get(key);
        if (obj) {
          const headers = new Headers();
          obj.writeHttpMetadata(headers);
          headers.set("etag", obj.httpEtag);
          if (key.endsWith(".m3u8") || key.endsWith(".json")) {
            headers.set("Cache-Control", "no-cache, no-store, must-revalidate");
          } else if (key.endsWith(".ts")) {
            headers.set("Content-Type", "video/mp2t");
            headers.set("Cache-Control", "public, max-age=31536000, immutable");
          }
          return new Response(obj.body, { headers });
        }
      }
    }

    // 2. Everything else -> the live container (player, /live before R2 sync,
    //    /healthz). getContainer returns a singleton instance for this Worker.
    const container = getContainer(env.AETHER_CONTAINER);
    return container.fetch(request);
  },
};
