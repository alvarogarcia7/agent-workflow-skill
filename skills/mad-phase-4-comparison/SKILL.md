---
name: mad-phase-4-comparison
description: Phase 4 of the multi-agent development pipeline (Ralph Wiggum loop). Compare the design with the actual implementation on the pushed commit, produce similarity reports per screen, and turn every gap below the target into child subtasks that re-enter the development loop.
---

# Phase 4: Comparison (Ralph Wiggum loop)

Inbox: `compare` (green pushes from Phase 3) or a schedule. Outbox: new TODO child tasks (re-enter Phase 1) and the reports.

One iteration: (1) take the design reference and the implementation of the pushed commit, (2) measure similarity (pixel, typography, layout; fonts included; **data excluded**) on a seeded dataset, (3) write `reports/similarity/<date>-<task>.md` with scores, targets and the exact differences, (4) create child subtasks for the gaps (the original task cannot be finished until its children are Done), (5) add the label `needs-review` to the original task when its criteria and comparison are satisfied (the user reviews implemented solutions, never plans), (6) archive the message.

Measurement principles: data rows (tables, lists, activity, charts) are masked identically on both sides; never tune seed data to the design; log every measurement change in the decision log.
Run: `scripts/ralph-loop.sh phase4 compare prompt.md`. Pipeline: `MULTI_AGENT_DEV_SKILL.md`.
