#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 4444J99
/**
 * build-workbench.mjs — bundle the workbench into brahma/web/public/workbench/vendor/.
 *
 * The bundle is a build artefact, not a source file: it is gitignored and rebuilt by
 * `npm run build:workbench` (which smoke.sh runs before booting the server). Serving
 * an unbuilt tree is a broken page, not a silent fallback, so the build has to be part
 * of any gate that claims the workbench works.
 *
 * `legalComments: "eof"` keeps the AGPL/MIT notices from the bundled dependencies in
 * the output. Minification must not strip attribution for code we redistribute.
 */

import { fileURLToPath, pathToFileURL } from "node:url";
import { createRequire } from "node:module";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(here, "..", "brahma", "web");

// esbuild lives in brahma/web/node_modules. Resolve it from there explicitly rather
// than relying on this script's own directory being inside that package tree.
const requireFromWeb = createRequire(path.join(web, "package.json"));
const { build } = await import(pathToFileURL(requireFromWeb.resolve("esbuild")).href);

const entry = path.join(web, "public", "workbench", "src", "main.js");
const outfile = path.join(web, "public", "workbench", "vendor", "workbench.js");

await build({
  entryPoints: [entry],
  outfile,
  bundle: true,
  format: "esm",
  target: ["chrome110", "safari16", "firefox110"],
  minify: true,
  sourcemap: false,
  legalComments: "eof",
  logLevel: "warning",
  define: {
    "process.env.NODE_ENV": '"production"'
  }
});

process.stdout.write(`workbench bundle -> ${path.relative(web, outfile)}\n`);
