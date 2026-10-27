"use strict";
/**
 * actions.js — The capability core.
 *
 * One canonical set of engine capabilities, each with a name, JSON schema, and
 * handler. The REST API, the MCP server, and BOTH ACP adapters are thin
 * presentations of this same registry — so a capability added here is instantly
 * available on every surface. This is the "ideal form": the protocol is a skin,
 * the capability is the body.
 */

const engine = require("./engine");
const catalog = require("./catalog");
const marketplace = require("../marketplace/marketplace");

const ACTIONS = {
  list_modules: {
    description: "List synthesis modules / organisms in the Brahma catalog.",
    cost: 0,
    schema: { type: "object", properties: {
      category: { type: "string", description: "Filter by category (engine, organism, ...)" },
      q: { type: "string", description: "Free-text search" }
    } },
    handler: (args = {}) => catalog.listModules({ category: args.category, q: args.q })
  },

  get_module: {
    description: "Get a single module's details and parameters.",
    cost: 0,
    schema: { type: "object", required: ["name"], properties: {
      name: { type: "string", description: "Module name, e.g. 'Azoth'" }
    } },
    handler: (args = {}) => {
      const m = catalog.getModule(args.name);
      if (!m) throw new Error(`unknown module: ${args.name}`);
      return m;
    }
  },

  get_organism_state: {
    description: "Live organism telemetry (coherence/entropy) from the running engine.",
    cost: 0,
    schema: { type: "object", properties: {} },
    handler: () => ({ online: engine.isOnline(), organisms: engine.organismState() })
  },

  render_specimen: {
    description: "Create a simulated specimen record from a module. Metered. Audio rendering and artifact completion are not connected; audioUrl is null.",
    cost: 1,
    schema: { type: "object", required: ["module"], properties: {
      module: { type: "string", description: "Source module name" },
      title: { type: "string" },
      creator: { type: "string", description: "Creator handle/email" },
      durationSec: { type: "number", description: "Specimen length in seconds (default 4)" }
    } },
    handler: (args = {}, context = {}) => engine.renderSpecimen(args, { ownerEmail: context.ownerEmail || null })
  },

  list_specimens: {
    description: "List specimens available in the marketplace.",
    cost: 0,
    schema: { type: "object", properties: {
      module: { type: "string" }, creator: { type: "string" }
    } },
    handler: (args = {}) => marketplace.listForSale(args)
  }
};

function listActions() {
  return Object.entries(ACTIONS).map(([name, a]) => ({
    name, description: a.description, inputSchema: a.schema, cost: a.cost
  }));
}

function getAction(name) { return ACTIONS[name] || null; }

/** Invoke a capability by name. Throws on unknown action / handler error. */
function invoke(name, args, context = {}) {
  const a = ACTIONS[name];
  if (!a) throw Object.assign(new Error(`unknown action: ${name}`), { code: "unknown_action" });
  return a.handler(args || {}, context);
}

module.exports = { ACTIONS, listActions, getAction, invoke };
