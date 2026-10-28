---
name: mad-phase-1-development
description: Phase 1 of the multi-agent development pipeline (Ralph Wiggum loop). Take the next TODO from the backlog, mark it In Progress and commit the backlog, develop with tests, consult an Opus agent for doubts and log the decision, run the same checks the CI/CD pipeline runs, commit the work, and send it to the review mailbox. Use when asked to run or supervise the development loop of a multi-agent pipeline.
---

# Phase 1: Development (Ralph Wiggum loop)

Inbox: the backlog (TODO tasks) and the `rework` mailbox (tasks rejected by Phase 2). Outbox: `review`.
Workers: several in parallel, each with its own worktree, branch and ports. Model: the strongest affordable, cheap models only with strong verification.

One iteration (fresh context, state on disk):

1. **Take the next TODO**, mark it `In Progress`, **commit the backlog** by itself. Rework messages come first (they are older work that came back).
2. **Develop** within your owned files, writing the tests as you go.
3. **Doubts → consult**: spawn an Opus agent read-only with a narrow brief, **decide**, write the decision in the decision log (id, why, alternatives). Do not ask the user.
4. **Run tests, validation and verification** = the same tasks the CI/CD pipeline would run (formatter, linter, type check, static analysis, unit/integration/UI tests), same order and flags. Fix until green.
5. **Commit as In Progress**: code, tests, docs, request files.
6. **Send to Phase 2**: `scripts/mailbox.sh send review <task-id> <message-file>` (task, branch+commit, changes, evidence, decisions, risks).

Run it: `scripts/ralph-loop.sh phase1 rework prompt.md` for rework first, or point the loop at your task source; `AGENT_CMD="claude -p --model sonnet"`.
The iteration prompt is `prompt.md` in this folder. Full pipeline: see `MULTI_AGENT_DEV_SKILL.md`.
