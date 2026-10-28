---
name: mad-phase-3-push
description: Phase 3 of the multi-agent development pipeline (Ralph Wiggum loop, exactly one worker). Push accepted commits in order of arrival, respecting a slow pipeline (push only when the last pipeline finished if pushes cancel runs), and when a pipeline goes red reproduce the failure locally, produce a fix on a small branch from the red commit and insert it after the red commit (Green, Green, Red, Fix, Green2, Green3).
---

# Phase 3: Push (Ralph Wiggum loop, one worker)

Inbox: `push` (from Phase 2). Outbox: `compare` (green). Only one worker, because it serialises the integration branch.

**When to push**
- Pipeline slow and runs get cancelled by new pushes → push **only when the last pipeline finished** (success or error).
- Otherwise → push **as soon as possible**.

**When a pipeline is red**: keep the history `Green -> Green -> Red -> Fix -> Green2 -> Green3`:
1. Identify the red commit and the failing job/test.
2. If it fails in CI but not locally, **change the local test setup so that it reproduces the failure first** (parallelism, timing, environment, flags, load).
3. Create `fix/<red-sha>` from the red commit; produce the fix (test, code, pipeline, config) and verify locally.
4. `scripts/insert-fix.sh <red-sha> fix/<red-sha> <integration-branch> --push`: rebases everything after Red onto the fix and pushes with `--force-with-lease` under the push lock. This is the **only** allowed history rewrite; announce it, and workers rebase afterwards.
5. Wait for the new pipeline; repeat if red.

Green → record the pipeline id on the task, forward to `compare`.
Run: `scripts/ralph-loop.sh phase3 push prompt.md`. Pipeline: `MULTI_AGENT_DEV_SKILL.md`.
