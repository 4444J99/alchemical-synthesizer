"use strict";
/**
 * jobs.js — one-at-a-time async runner for approved composition work.
 *
 * Rendering shells out to sclang and takes tens of seconds. A request handler must
 * not block on that, and a browser must not be able to start ten of them at once on
 * a memory-constrained host. So: a bounded FIFO queue, concurrency one, and a job
 * record the caller polls.
 *
 * The runner never decides *whether* work may run — it is handed only jobs whose
 * approval has already been accepted by a human.
 */

const crypto = require("node:crypto");

const STATES = Object.freeze({
  QUEUED: "queued",
  RUNNING: "running",
  COMPLETED: "completed",
  FAILED: "failed"
});

function createJobRunner({ execute, now = () => Date.now(), maxQueued = 16, idFactory } = {}) {
  if (typeof execute !== "function") throw new Error("createJobRunner requires an execute function");

  const jobs = new Map();
  const queue = [];
  const waiters = [];
  let running = null;
  let activeController = null;

  const newId = idFactory || (() => "job_" + crypto.randomBytes(6).toString("hex"));

  function view(job) {
    return { ...job };
  }

  function settle() {
    for (const resolve of waiters.splice(0)) resolve();
  }

  function tick() {
    if (running) return;
    const id = queue.shift();
    if (!id) {
      settle();
      return;
    }

    const job = jobs.get(id);
    running = id;
    const controller = new AbortController();
    activeController = controller;
    job.state = STATES.RUNNING;
    job.startedAt = new Date(now()).toISOString();

    Promise.resolve()
      .then(() => {
        // stopAll may run in the same turn as enqueue, before execution begins.
        controller.signal.throwIfAborted();
        return execute(job, { signal: controller.signal });
      })
      .then((result) => {
        if (job.state !== STATES.RUNNING) return;
        job.state = STATES.COMPLETED;
        job.result = result === undefined ? null : result;
      })
      .catch((err) => {
        if (job.state !== STATES.RUNNING) return;
        job.state = STATES.FAILED;
        job.error = err && err.message ? err.message : String(err);
      })
      .then(() => {
        if (!job.finishedAt) job.finishedAt = new Date(now()).toISOString();
        activeController = null;
        running = null;
        // Yield so the completion is observable before the next job starts.
        setImmediate(tick);
      });
  }

  /** The agent layer checks authority before cancelling active and queued work. */
  function stopAll() {
    const stopped = [];
    for (const id of [running, ...queue]) {
      const job = jobs.get(id);
      if (!job || (job.state !== STATES.RUNNING && job.state !== STATES.QUEUED)) continue;
      job.state = STATES.FAILED;
      job.error = "stopped by human";
      job.finishedAt = new Date(now()).toISOString();
      stopped.push(view(job));
    }
    queue.length = 0;
    if (activeController && !activeController.signal.aborted) {
      activeController.abort(new Error("stopped by human"));
    }
    // Keep the execution slot until the aborted process settles. A new human
    // run must not overlap a process that is still shutting down.
    if (!running) settle();
    return { ok: true, jobs: stopped };
  }

  /** Queue work. Returns immediately; the job's state is polled via get(). */
  function enqueue({ approvalId = null, tool, args = {} } = {}) {
    if (typeof tool !== "string" || !tool) {
      return { ok: false, code: "bad_tool", message: "enqueue requires a tool name" };
    }
    if (queue.length >= maxQueued) {
      return { ok: false, code: "queue_full", message: `queue holds ${maxQueued} jobs already` };
    }

    const job = {
      id: newId(),
      approvalId,
      tool,
      args,
      state: STATES.QUEUED,
      createdAt: new Date(now()).toISOString(),
      startedAt: null,
      finishedAt: null,
      result: null,
      error: null
    };
    jobs.set(job.id, job);
    queue.push(job.id);
    tick();
    return { ok: true, job: view(job) };
  }

  function get(id) {
    const job = jobs.get(id);
    return job ? view(job) : null;
  }

  function list() {
    return [...jobs.values()].map(view);
  }

  /** Resolves when nothing is queued or running. Used by tests and shutdown. */
  function drain() {
    if (!running && queue.length === 0) return Promise.resolve();
    return new Promise((resolve) => waiters.push(resolve));
  }

  return { enqueue, get, list, drain, stopAll, STATES, get pending() { return queue.length; }, get active() { return running; } };
}

module.exports = { createJobRunner, STATES };
