# Design-parity loop (optional)

Goal: every screen reaches a target similarity (for example 95%: pixel + typography + layout, **data excluded**) against a design reference, measured by a script on a seeded dataset.

- Workers claim an unassigned open parity child task of their screen shard, copy the design's actual CSS/DOM values (never approximate), keep every test id, re-measure through `scripts/heavy.sh`, and close the child with the measured evidence.
- Measurement changes must be principled and logged as decisions: data rows (list/table rows, activity entries, chart bars) are masked identically on both sides, and seed values are never tuned to the design.
- Findings go into the child tasks' notes so any worker can pick them up cold (handover template).
- Measurement runs are heavy: one at a time per agent, through the limiter.
