"use strict";
/**
 * approval.js — the propose → accept → run boundary.
 *
 * An agent may *propose* work. It may never accept its own proposal, and accepting
 * a proposal never executes it. Those are three separate acts, held in three
 * separate calls, because collapsing them is how "no auto-run" quietly becomes
 * "runs itself".
 *
 * States:
 *
 *   proposed ──accept(human)──> accepted ──run(human)──> running ──> completed
 *      │                            │                        └────> failed
 *      └──reject(human)──> rejected └──reject(human)──> rejected
 *
 * Every transition returns {ok:true, approval} or {ok:false, code, message}. Nothing
 * throws for ordinary misuse: the caller is an API surface and needs a code.
 */

const crypto = require("node:crypto");

const STATES = Object.freeze({
  PROPOSED: "proposed",
  ACCEPTED: "accepted",
  REJECTED: "rejected",
  RUNNING: "running",
  COMPLETED: "completed",
  FAILED: "failed"
});

// Legal edges. Anything absent here is an invalid transition, full stop.
const EDGES = {
  [STATES.PROPOSED]: [STATES.ACCEPTED, STATES.REJECTED],
  [STATES.ACCEPTED]: [STATES.RUNNING, STATES.REJECTED],
  [STATES.RUNNING]: [STATES.COMPLETED, STATES.FAILED],
  [STATES.REJECTED]: [],
  [STATES.COMPLETED]: [],
  [STATES.FAILED]: []
};

const MAX_APPROVALS = 200;

function createApprovalStore({ now = () => Date.now(), idFactory } = {}) {
  const items = new Map();
  const order = [];

  const newId = idFactory || (() => "apv_" + crypto.randomBytes(6).toString("hex"));

  function record(approval) {
    items.set(approval.id, approval);
    order.push(approval.id);
    while (order.length > MAX_APPROVALS) {
      const evicted = order.shift();
      items.delete(evicted);
    }
    return approval;
  }

  function view(a) {
    return { ...a };
  }

  function fail(code, message) {
    return { ok: false, code, message };
  }

  /**
   * An agent (or a human) proposes work. This never executes anything.
   */
  function propose({ tool, args = {}, summary = "", proposedBy = "agent" } = {}) {
    if (typeof tool !== "string" || !tool) return fail("bad_tool", "proposal requires a tool name");

    const approval = {
      id: newId(),
      tool,
      args,
      summary: String(summary).slice(0, 500),
      proposedBy: proposedBy === "human" ? "human" : "agent",
      state: STATES.PROPOSED,
      proposedAt: new Date(now()).toISOString(),
      decidedAt: null,
      decidedBy: null,
      reason: null,
      runner: null,
      result: null,
      error: null
    };
    record(approval);
    return { ok: true, approval: view(approval) };
  }

  function transition(id, to, { actor, patch = {} } = {}) {
    const approval = items.get(id);
    if (!approval) return fail("unknown_approval", `No approval ${id}`);

    if (!(EDGES[approval.state] || []).includes(to)) {
      return fail("invalid_transition", `Cannot move ${approval.state} → ${to}`);
    }
    Object.assign(approval, patch);
    approval.state = to;
    return { ok: true, approval: view(approval) };
  }

  function accept(id, { actor } = {}) {
    // The human gate. An agent accepting its own proposal would defeat the
    // boundary entirely, so the actor is checked before the state machine runs.
    if (actor !== "human") return fail("forbidden", "Only a human may accept a proposal");
    return transition(id, STATES.ACCEPTED, {
      actor,
      patch: { decidedAt: new Date(now()).toISOString(), decidedBy: "human" }
    });
  }

  function reject(id, { actor, reason = "" } = {}) {
    if (actor !== "human") return fail("forbidden", "Only a human may reject a proposal");
    return transition(id, STATES.REJECTED, {
      actor,
      patch: {
        decidedAt: new Date(now()).toISOString(),
        decidedBy: "human",
        reason: String(reason).slice(0, 500)
      }
    });
  }

  /** Called by the runner. Only an accepted approval may start. */
  function start(id, { runner } = {}) {
    const approval = items.get(id);
    if (!approval) return fail("unknown_approval", `No approval ${id}`);
    if (approval.state !== STATES.ACCEPTED) {
      return fail("not_accepted", `Approval ${id} is ${approval.state}, not accepted`);
    }
    return transition(id, STATES.RUNNING, { patch: { runner: runner || null } });
  }

  function complete(id, result) {
    return transition(id, STATES.COMPLETED, { patch: { result } });
  }

  function failRun(id, error) {
    return transition(id, STATES.FAILED, { patch: { error: String(error) } });
  }

  function get(id) {
    const approval = items.get(id);
    return approval ? view(approval) : null;
  }

  function list() {
    return order.map((id) => view(items.get(id))).filter(Boolean);
  }

  return { propose, accept, reject, start, complete, failRun, get, list, STATES };
}

module.exports = { createApprovalStore, STATES, EDGES };
