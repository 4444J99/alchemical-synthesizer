# Workbench — licence boundary

This directory is **AGPL-3.0-or-later**. It is a separate document from the Visual
Cortex page at `/` (which is MIT with an LGPL p5.js script tag). They never share a
document, so the licences do not mix.

## What lives here

| Path | Role |
|---|---|
| `index.html` | the page shell |
| `workbench.css` | styling |
| `src/` | workbench sources (editor, socket, Strudel output driver, UI) |
| `vendor/workbench.js` | **build artefact** — gitignored, produced by `npm run build:workbench` |
| `CHANGES` | record of any modification to bundled dependency source |

## Building

```sh
npm --prefix brahma/web run build:workbench
```

The bundle is not committed. Serving the page without building it produces a broken
page, which is why `tools/smoke.sh` builds before it boots the server.

## How the sound path works

Strudel supplies the pattern language and the clock. Its own WebAudio output is not
used: `repl({ defaultOutput })` hands every scheduled hap to `src/strudel.js`, which
translates it into a Brahma `event` frame and sends it over the typed WebSocket. The
gateway maps that to `/brahma/live/play`. Brahma supplies the sound.

## Licence obligations in force

- Source is offered at `GET /workbench/source.json` and linked in the page footer.
- `LICENSES/AGPL-3.0-or-later.txt` ships the full text.
- `NOTICE` at the repo root lists every bundled package with version and licence.
- Bundled dependency source is unmodified; modifications would be recorded in `CHANGES`.
- No proprietary asset, and nothing from `product/`, is loaded into this page.
- The product name does not contain "Strudel"; the UI says "Strudel pattern language"
  (nominative use).

This is engineering diligence, not legal advice. Hosting this page as part of a paid
commercial service needs a licence review first.
