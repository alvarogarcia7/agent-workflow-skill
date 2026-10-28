---
name: mad-phase-2-review
description: Phase 2 of the multi-agent development pipeline (Ralph Wiggum loop, small fast model such as Haiku). Review each task in the review mailbox against its acceptance criteria and evidence, send defects back as rework with child subtasks, otherwise mark the task Done, run or record the journeys/videos, and forward it to the push mailbox in order of arrival (FIFO).
---

# Phase 2: Review (Ralph Wiggum loop, small model)

Inbox: `review` (from Phase 1). Outbox: `push` (accepted) and `rework` (rejected, back to Phase 1). Messages are processed **in order of arrival**.
Model: a small fast one (e.g. Haiku): the reviewer checks against explicit criteria and evidence; it does not design or develop.

One iteration: claim the oldest `review` message →
1. check criteria ↔ tests ↔ evidence, re-run the relevant tests; scope, decisions, leftovers;
2. **reject** with reasons (+ child subtasks per defect, parent stays In Progress) **or**
3. **mark Done** through the backlog CLI (criteria/DoD checks, final summary, `Done`), commit the backlog;
4. **videos / journeys**: run or record them and make sure the description file has an entry; failures go back as rework;
5. forward to `push`.

Run: `scripts/ralph-loop.sh phase2 review prompt.md` with `AGENT_CMD="claude -p --model haiku"`. Pipeline: `MULTI_AGENT_DEV_SKILL.md`.
