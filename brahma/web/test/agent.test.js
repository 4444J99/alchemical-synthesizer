"use strict";

/**
 * agent.test.js — the composition loop's guarantees, tested at the unit level.
 *
 * The claims under test are the ones that would make the feature dishonest if they
 * broke:
 *   - proposing never executes anything
 *   - an agent cannot accept its own proposal
 *   - accepting is not running
 *   - an unavailable provider is reported as unavailable, never as an empty pattern
 *
 * The render itself is injected here: this file never shells out to sclang, so it
 * stays fast and hermetic on a host without SuperCollider.
 */

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createApprovalStore } = require("../lib/agent/approval");
const { createJobRunner } = require("../lib/agent/jobs");
const { createProviderRegistry, validateEvents, mockProposal } = require("../lib/agent/providers");
const { createAgentLayer } = require("../lib/agent");

const REPO_ROOT = path.resolve(__dirname, "../../..");

// --------------------------------------------------------------------- approvals

test("approval: a proposal starts in `proposed` and carries its payload", () => {
  const store = createApprovalStore({ now: () => 1_700_000_000_000 });
  const result = store.propose({ tool: "render_pattern", args: { events: [] }, summary: "a motif" });

  assert.equal(result.ok, true);
  assert.equal(result.approval.state, "proposed");
  assert.equal(result.approval.proposedBy, "agent");
  assert.equal(result.approval.decidedAt, null);
  assert.equal(result.approval.summary, "a motif");
});

test("approval: an agent may not accept or reject its own proposal", () => {
  const store = createApprovalStore();
  const { approval } = store.propose({ tool: "render_pattern" });

  assert.equal(store.accept(approval.id, { actor: "agent" }).code, "forbidden");
  assert.equal(store.reject(approval.id, { actor: "agent" }).code, "forbidden");
  assert.equal(store.get(approval.id).state, "proposed", "a refused gate leaves state untouched");
});

test("approval: accepting does not run, and run requires accepted state", () => {
  const store = createApprovalStore();
  const { approval } = store.propose({ tool: "render_pattern" });

  const early = store.start(approval.id);
  assert.equal(early.ok, false);
  assert.equal(early.code, "not_accepted");

  const accepted = store.accept(approval.id, { actor: "human" });
  assert.equal(accepted.ok, true);
  assert.equal(accepted.approval.state, "accepted");
  assert.equal(accepted.approval.decidedBy, "human");

  // Accepting is a decision, not an execution. The store has no side effects.
  const started = store.start(approval.id, { runner: "job_1" });
  assert.equal(started.ok, true);
  assert.equal(started.approval.state, "running");
  assert.equal(started.approval.runner, "job_1");
});

test("approval: invalid transitions are refused rather than coerced", () => {
  const store = createApprovalStore();
  const { approval } = store.propose({ tool: "render_pattern" });

  store.accept(approval.id, { actor: "human" });
  assert.equal(store.accept(approval.id, { actor: "human" }).code, "invalid_transition");
  assert.equal(store.complete(approval.id, {}).code, "invalid_transition");

  store.start(approval.id);
  assert.equal(store.reject(approval.id, { actor: "human" }).code, "invalid_transition");

  const done = store.complete(approval.id, { measured: { rms_dbfs: -20 } });
  assert.equal(done.ok, true);
  assert.equal(done.approval.state, "completed");

  const rerun = store.start(approval.id);
  assert.equal(rerun.ok, false, "a completed approval cannot re-run");
  assert.ok(["not_accepted", "invalid_transition"].includes(rerun.code));
});

test("approval: a rejected proposal can never run", () => {
  const store = createApprovalStore();
  const { approval } = store.propose({ tool: "render_pattern" });
  store.reject(approval.id, { actor: "human", reason: "not this" });

  assert.equal(store.get(approval.id).state, "rejected");
  assert.equal(store.get(approval.id).reason, "not this");
  assert.equal(store.start(approval.id).code, "not_accepted");
});

test("approval: unknown ids are a typed miss, not a throw", () => {
  const store = createApprovalStore();
  assert.equal(store.accept("apv_nope", { actor: "human" }).code, "unknown_approval");
  assert.equal(store.get("apv_nope"), null);
});

test("approval: the store is bounded so a runaway agent cannot grow it forever", () => {
  let n = 0;
  const store = createApprovalStore({ idFactory: () => `apv_${++n}` });
  for (let i = 0; i < 260; i += 1) store.propose({ tool: "render_pattern" });

  const list = store.list();
  assert.equal(list.length, 200);
  assert.equal(list[0].id, "apv_61", "the oldest entries are evicted first");
});

// -------------------------------------------------------------------------- jobs

test("jobs: FIFO, one at a time", async () => {
  const order = [];
  let concurrent = 0;
  let maxConcurrent = 0;

  const runner = createJobRunner({
    execute: async (job) => {
      concurrent += 1;
      maxConcurrent = Math.max(maxConcurrent, concurrent);
      order.push(`start:${job.tool}`);
      await new Promise((resolve) => setTimeout(resolve, 10));
      order.push(`end:${job.tool}`);
      concurrent -= 1;
      return { ok: true };
    }
  });

  runner.enqueue({ tool: "a" });
  runner.enqueue({ tool: "b" });
  runner.enqueue({ tool: "c" });
  await runner.drain();

  assert.deepEqual(order, ["start:a", "end:a", "start:b", "end:b", "start:c", "end:c"]);
  assert.equal(maxConcurrent, 1, "concurrency is one, by construction");
});

test("jobs: a failure is recorded and does not stall the queue", async () => {
  const runner = createJobRunner({
    execute: async (job) => {
      if (job.tool === "bad") throw new Error("render exploded");
      return { fine: true };
    }
  });

  const bad = runner.enqueue({ tool: "bad" });
  const good = runner.enqueue({ tool: "good" });
  await runner.drain();

  assert.equal(runner.get(bad.job.id).state, "failed");
  assert.match(runner.get(bad.job.id).error, /render exploded/);
  assert.equal(runner.get(good.job.id).state, "completed");
  assert.deepEqual(runner.get(good.job.id).result, { fine: true });
});

test("jobs: the queue is bounded and refuses rather than dropping work silently", () => {
  const runner = createJobRunner({
    execute: async () => new Promise(() => {}), // never settles
    maxQueued: 2
  });

  assert.equal(runner.enqueue({ tool: "a" }).ok, true); // starts immediately
  assert.equal(runner.enqueue({ tool: "b" }).ok, true);
  assert.equal(runner.enqueue({ tool: "c" }).ok, true);

  const overflow = runner.enqueue({ tool: "d" });
  assert.equal(overflow.ok, false);
  assert.equal(overflow.code, "queue_full");
});

test("jobs: unknown job is null, not an exception", () => {
  const runner = createJobRunner({ execute: async () => null });
  assert.equal(runner.get("job_nope"), null);
});

// --------------------------------------------------------------------- providers

test("providers: availability is probed and reported with a reason", () => {
  const registry = createProviderRegistry({ env: {} });
  const list = registry.list();
  const byName = Object.fromEntries(list.map((p) => [p.name, p]));

  assert.equal(byName.mock.available, true);
  assert.equal(byName.claude.available, false);
  assert.match(byName.claude.reason, /not_configured/);
  assert.match(byName.tidal.reason, /not_installed/);
  assert.match(byName.sonicpi.reason, /not_installed/);

  for (const p of list) {
    assert.ok(p.reason, `${p.name} must state why it is available or not`);
  }
});

test("providers: claude is available only with a key, and needs a pinned model", async () => {
  const withKey = createProviderRegistry({ env: { ANTHROPIC_API_KEY: "k" } });
  assert.equal(withKey.list().find((p) => p.name === "claude").available, true);

  // Available but unpinned: a typed refusal, not a guess at a model id.
  const unpinned = await withKey.propose("claude", { prompt: "x" });
  assert.equal(unpinned.ok, false);
  assert.match(unpinned.message, /BRAHMA_CLAUDE_MODEL/);
});

test("providers: an unavailable provider refuses, it never returns an empty pattern", async () => {
  const registry = createProviderRegistry({ env: {} });

  for (const name of ["tidal", "sonicpi"]) {
    const result = await registry.propose(name, { prompt: "anything" });
    assert.equal(result.ok, false);
    assert.equal(result.code, "provider_unavailable");
    assert.match(result.message, /not_installed/);
    assert.equal(result.events, undefined, "no events field may exist on a refusal");
  }
});

test("providers: an injected transport is parsed and normalised", async () => {
  const registry = createProviderRegistry({
    env: { ANTHROPIC_API_KEY: "k", BRAHMA_CLAUDE_MODEL: "pinned-model" },
    transport: async () => '```json\n{"summary":"two notes","events":[{"time":1,"note":55,"vel":0.5,"dur":0.25},{"time":0,"note":48,"vel":0.9,"dur":0.5}]}\n```'
  });

  const result = await registry.propose("claude", { prompt: "two notes" });
  assert.equal(result.ok, true);
  assert.equal(result.summary, "two notes");
  assert.deepEqual(result.events.map((e) => e.note), [48, 55], "events come back time-ordered");
});

test("providers: a malformed model response is refused", async () => {
  const registry = createProviderRegistry({
    env: { ANTHROPIC_API_KEY: "k", BRAHMA_CLAUDE_MODEL: "pinned-model" },
    transport: async () => "I would love to help! Here is a melody: C D E"
  });

  const result = await registry.propose("claude", { prompt: "x" });
  assert.equal(result.ok, false);
  assert.equal(result.code, "provider_error");
});

test("providers: the mock motif is deterministic and needs no model", () => {
  const a = mockProposal("rain on glass");
  const b = mockProposal("rain on glass");
  const c = mockProposal("something else");

  assert.deepEqual(a, b);
  assert.notDeepEqual(a.events, c.events);
  assert.equal(a.events.length, 8);
  assert.match(a.summary, /no model was called/, "the label must not imply a model was used");
});

test("providers: event validation rejects out-of-range values", () => {
  assert.equal(validateEvents([]), null);
  assert.equal(validateEvents([{ time: 0, note: 200 }]), null, "note must be MIDI");
  assert.equal(validateEvents([{ time: -1, note: 60 }]), null, "time must not be negative");
  assert.equal(validateEvents([{ time: 0, note: 60, vel: 3 }]), null, "velocity is 0..1");
  assert.equal(validateEvents([{ time: 0, note: 60, dur: 0 }]), null, "duration must be positive");
  assert.equal(validateEvents([{ time: 0, note: 60 }]).length, 1, "defaults fill vel and dur");
});

// ---------------------------------------------------------------- the whole loop

function failingExecCalls() {
  const calls = [];
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-agent-test-"));

  const execFile = async (file, args) => {
    calls.push({ file, args });
    // The renderer's contract: write a WAV, then measure it.
    if (args.some((a) => String(a).includes("render-pattern.sh"))) {
      fs.writeFileSync(args[2], "RIFF-fake-wav");
      return { stdout: "", stderr: "" };
    }
    if (args.some((a) => String(a).includes("analyze_audio.py"))) {
      const summaryPath = args[args.indexOf("--summary-json") + 1];
      fs.writeFileSync(summaryPath, JSON.stringify({
        verdict: "non_silent",
        peak_dbfs: -12.5,
        rms_dbfs: -24.0,
        silence_ratio: 0.25,
        non_silent_seconds: 3.0,
        duration_s: 4.0
      }));
      return { stdout: "", stderr: "" };
    }
    throw new Error(`unexpected exec: ${file} ${args.join(" ")}`);
  };

  return { calls, scratch, execFile };
}

test("loop: propose → accept → run, with nothing executing before the human acts", async () => {
  const { calls, scratch, execFile } = failingExecCalls();
  const layer = createAgentLayer({ repoRoot: REPO_ROOT, execFile, scratchRoot: scratch });

  const proposal = await layer.propose({ provider: "mock", prompt: "a slow chord" });
  assert.equal(proposal.ok, true);
  assert.equal(proposal.approval.state, "proposed");
  assert.equal(calls.length, 0, "proposing must not execute anything");

  const accepted = layer.accept(proposal.approval.id, { actor: "human" });
  assert.equal(accepted.ok, true);
  assert.equal(calls.length, 0, "accepting must not execute anything");
  assert.equal(layer.runner.list().length, 0, "accepting must not queue a job");

  const started = layer.run(proposal.approval.id, { actor: "human" });
  assert.equal(started.ok, true);
  assert.equal(layer.approvals.get(proposal.approval.id).state, "running");

  await layer.runner.drain();

  const approval = layer.approvals.get(proposal.approval.id);
  assert.equal(approval.state, "completed");
  assert.equal(approval.result.events, proposal.events.length);
  assert.equal(approval.result.measured.verdict, "non_silent");
  assert.equal(approval.result.measured.peak_dbfs, -12.5);

  const job = layer.runner.get(started.job.id);
  assert.equal(job.state, "completed");

  // The two CLIs the plan names were actually the ones invoked, in order.
  assert.equal(calls.length, 2);
  assert.match(calls[0].args[0], /forge\/render-pattern\.sh$/);
  assert.match(calls[1].args[0], /forge\/analyze_audio\.py$/);
});

test("loop: an agent cannot run what a human accepted", () => {
  const { scratch, execFile } = failingExecCalls();
  const layer = createAgentLayer({ repoRoot: REPO_ROOT, execFile, scratchRoot: scratch });

  return layer.propose({ provider: "mock", prompt: "x" }).then((proposal) => {
    layer.accept(proposal.approval.id, { actor: "human" });

    const denied = layer.run(proposal.approval.id, { actor: "agent" });
    assert.equal(denied.ok, false);
    assert.equal(denied.code, "forbidden");
    assert.equal(layer.runner.list().length, 0, "a refused run queues nothing");
    assert.equal(layer.approvals.get(proposal.approval.id).state, "accepted");
  });
});

test("loop: a run that fails marks the approval failed with the reason", async () => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brahma-agent-test-"));
  const execFile = async (file, args) => {
    if (args.some((a) => String(a).includes("render-pattern.sh"))) {
      throw new Error("sclang not found");
    }
    return { stdout: "", stderr: "" };
  };

  const layer = createAgentLayer({ repoRoot: REPO_ROOT, execFile, scratchRoot: scratch });
  const proposal = await layer.propose({ provider: "mock", prompt: "x" });
  layer.accept(proposal.approval.id, { actor: "human" });
  layer.run(proposal.approval.id, { actor: "human" });
  await layer.runner.drain();

  const approval = layer.approvals.get(proposal.approval.id);
  assert.equal(approval.state, "failed");
  assert.match(approval.error, /sclang not found/);
});

test("loop: a proposal the provider refused is never filed", async () => {
  const { scratch, execFile } = failingExecCalls();
  const layer = createAgentLayer({ repoRoot: REPO_ROOT, execFile, scratchRoot: scratch });

  const refused = await layer.propose({ provider: "tidal", prompt: "x" });
  assert.equal(refused.ok, false);
  assert.equal(layer.approvals.list().length, 0, "nothing is filed for work that cannot run");
});

test("loop: the tool catalogue declares which tools need a human", () => {
  const { scratch, execFile } = failingExecCalls();
  const layer = createAgentLayer({ repoRoot: REPO_ROOT, execFile, scratchRoot: scratch });

  const byName = Object.fromEntries(layer.toolset().map((t) => [t.name, t]));
  assert.equal(byName.render_pattern.approval, "required");
  assert.equal(byName.analyze_audio.approval, "none");
  assert.equal(byName.engine_status.approval, "none");
});
