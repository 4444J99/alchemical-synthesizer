"use strict";
/**
 * index.js — the agent composition loop, wired.
 *
 * propose  (agent or human)  → an approval in `proposed`, nothing runs
 * accept   (human only)      → `accepted`, still nothing runs
 * run      (human only)      → queued, executed one at a time
 * inspect  (anyone authed)   → the job record and the measured result
 *
 * The three acts are separate calls by construction. There is no code path from
 * propose to execute that does not pass through a human actor.
 */

const { createApprovalStore } = require("./approval");
const { createJobRunner } = require("./jobs");
const { createProviderRegistry, validateEvents } = require("./providers");
const { createTools } = require("./tools");

function createAgentLayer({
  repoRoot,
  engineHealth,
  env = process.env,
  execFile,
  scratchRoot,
  now = () => Date.now(),
  transport
} = {}) {
  const approvals = createApprovalStore({ now });
  const providers = createProviderRegistry({ env, transport, now });
  const tools = createTools({ repoRoot, execFile, scratchRoot, engineHealth, now });

  const runner = createJobRunner({
    now,
    maxQueued: 16,
    execute: async (job, { signal }) => {
      try {
        const result = await tools.run(job.tool, job.args, { signal });
        if (job.approvalId && !signal.aborted) approvals.complete(job.approvalId, result);
        return result;
      } catch (err) {
        if (job.approvalId && !signal.aborted) approvals.failRun(job.approvalId, err.message);
        throw err;
      }
    }
  });

  /** File a proposal. Two paths:
   *   1. Agent-composed: caller supplies `events` (already validated shape).
   *      No provider is called; the connected agent composed using its own
   *      allotment. This is the preferred path for MCP clients.
   *   2. Provider-composed: caller supplies `prompt` (+ optional `provider`);
   *      the server asks the provider for events.
   *  Nothing runs either way. */
  async function propose({ provider = "mock", prompt = "", events, summary, duration, proposedBy = "agent" } = {}) {
    let resolvedProvider = provider || "mock";
    let resolvedEvents = null;
    let resolvedSummary = "";

    if (events !== undefined) {
      // Agent-composed path: validate the supplied events, no provider call.
      const validated = validateEvents(events);
      if (!validated) {
        return { ok: false, code: "bad_events", message: "events must be a non-empty array of valid note events (time 0-3600, note 0-127, vel 0-1, dur 0-30, at most 512)" };
      }
      resolvedEvents = validated;
      resolvedProvider = "agent";
      resolvedSummary = String(summary || "agent-composed pattern").slice(0, 500);
    } else {
      const proposal = await providers.propose(resolvedProvider, { prompt });
      if (!proposal.ok) return proposal;
      resolvedEvents = proposal.events;
      resolvedSummary = proposal.summary;
      resolvedProvider = proposal.provider;
    }

    // The accepted payload is exactly the payload that will run: the events are
    // frozen into the approval, not re-requested from the provider at run time.
    const filed = approvals.propose({
      tool: "render_pattern",
      args: { events: resolvedEvents, duration: duration === undefined ? null : Number(duration), label: resolvedProvider },
      summary: resolvedSummary,
      proposedBy
    });
    if (!filed.ok) return filed;

    return {
      ok: true,
      provider: resolvedProvider,
      approval: filed.approval,
      summary: resolvedSummary,
      events: resolvedEvents
    };
  }

  function accept(id, { actor } = {}) {
    return approvals.accept(id, { actor });
  }

  function reject(id, { actor, reason } = {}) {
    return approvals.reject(id, { actor, reason });
  }

  /** Queue an accepted approval for execution. Human only, and never automatic. */
  function run(id, { actor } = {}) {
    if (actor !== "human") {
      return { ok: false, code: "forbidden", message: "Only a human may run an accepted proposal" };
    }

    const approval = approvals.get(id);
    if (!approval) return { ok: false, code: "unknown_approval", message: `No approval ${id}` };
    if (approval.state !== approvals.STATES.ACCEPTED) {
      return { ok: false, code: "not_accepted", message: `Approval ${id} is ${approval.state}, not accepted` };
    }

    const queued = runner.enqueue({ approvalId: id, tool: approval.tool, args: approval.args });
    if (!queued.ok) {
      approvals.failRun(id, queued.message);
      return queued;
    }

    const started = approvals.start(id, { runner: queued.job.id });
    if (!started.ok) return started;

    return { ok: true, approval: started.approval, job: queued.job };
  }

  /** Stop all active and queued renders. Cancellation is terminal. Human only. */
  function stop({ actor } = {}) {
    if (actor !== "human") {
      return { ok: false, code: "forbidden", message: "Only a human may stop renders" };
    }
    const cancelled = runner.stopAll();
    for (const job of cancelled.jobs) {
      if (job.approvalId) approvals.failRun(job.approvalId, job.error);
    }
    return {
      ok: true,
      stopped: cancelled.jobs.length,
      jobs: cancelled.jobs.map((job) => job.id),
      message: cancelled.jobs.length ? "Render cancellation requested; queued work cleared" : "No render jobs to stop"
    };
  }

  return {
    approvals,
    providers,
    tools,
    runner,
    propose,
    accept,
    reject,
    run,
    stop,
    available: () => providers.list(),
    toolset: () => tools.catalogue()
  };
}

module.exports = { createAgentLayer };
