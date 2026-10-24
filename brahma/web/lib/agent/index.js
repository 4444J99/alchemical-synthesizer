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
const { createProviderRegistry } = require("./providers");
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
    execute: async (job) => {
      try {
        const result = await tools.run(job.tool, job.args);
        if (job.approvalId) approvals.complete(job.approvalId, result);
        return result;
      } catch (err) {
        if (job.approvalId) approvals.failRun(job.approvalId, err.message);
        throw err;
      }
    }
  });

  /** Ask a provider for a pattern, then file it as a proposal. Nothing runs. */
  async function propose({ provider = "mock", prompt = "", duration, proposedBy = "agent" } = {}) {
    const proposal = await providers.propose(provider, { prompt });
    if (!proposal.ok) return proposal;

    // The accepted payload is exactly the payload that will run: the events are
    // frozen into the approval, not re-requested from the provider at run time.
    const filed = approvals.propose({
      tool: "render_pattern",
      args: { events: proposal.events, duration: duration === undefined ? null : Number(duration), label: provider },
      summary: proposal.summary,
      proposedBy
    });
    if (!filed.ok) return filed;

    return {
      ok: true,
      provider: proposal.provider,
      approval: filed.approval,
      summary: proposal.summary,
      events: proposal.events
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

  return {
    approvals,
    providers,
    tools,
    runner,
    propose,
    accept,
    reject,
    run,
    available: () => providers.list(),
    toolset: () => tools.catalogue()
  };
}

module.exports = { createAgentLayer };
