# Multi-agent development pipeline (four Ralph Wiggum loops)

A backlog is developed by four loops that run side by side. Each loop is a **Ralph Wiggum loop**: it repeats the same prompt with a **fresh context** every iteration and keeps all state on disk (git, the backlog, mailbox files), never in an agent's memory. The loops are connected by **mailboxes**: when a phase finishes an item it sends a message to the next phase's mailbox; each phase processes its mailbox **FIFO (in order of arrival)**.

```
 backlog TODO ──► [1 Development] ──review──► [2 Review] ──push──► [3 Push] ──compare──► [4 Comparison]
                       ▲   ▲                      │                    │                      │
                       │   └────── rework ────────┘                    │                      │
                       └──────── new TODO child tasks (gaps) ──────────┴──────────────────────┘
```

| Phase | Skill | Model | Workers | Inbox | Outbox |
|---|---|---|---|---|---|
| 1 Development | `mad-phase-1-development` | strongest affordable | many (own worktree/ports) | backlog TODO, `rework` | `review` |
| 2 Review | `mad-phase-2-review` | small/fast (Haiku) | 1–few | `review` | `push`, `rework` |
| 3 Push | `mad-phase-3-push` | mid | exactly 1 | `push` | `compare` |
| 4 Comparison | `mad-phase-4-comparison` | mid/small | 1–few | `compare` | TODO children |

Scripts: `skills/multi-agent-workflow/scripts/` (`mailbox.sh`, `ralph-loop.sh`, `insert-fix.sh`, `safe-push.sh`, `ci-trigger.sh`, `heavy.sh`). In the phase skills `scripts/x.sh` means that folder. The generic playbook (roles, decisions, briefs, CI, lessons) is `skills/multi-agent-workflow/SKILL.md`; the per-project settings live in the project's `WORKFLOW.md` (template in `templates/`).

## Intake (before Phase 1)
Every request from the user (new feature, change, bug report, feedback) becomes a backlog task first: search, then create a child of the closest task (reopen a Done parent) or a new task, quote the user, write measurable criteria, and tell the user the task id. A requirement added to a task in progress is added as a criterion and forwarded to its agent. Only tasks enter Phase 1. **No review gate before implementation**: refinement agents write the design and child tasks, the open questions go to the user once in a batch (each with a recommended default), answers become decisions, and the children go straight to Phase 1. When Phase 4 is satisfied the task or epic gets the label `needs-review`; the coordinator's report lists those tasks so the user reviews a working solution, not a plan. The same list is kept in `NEEDS_REVIEW.md` at the repository root (template `templates/NEEDS_REVIEW.md`: task, what, where to look, decisions); the agent that finishes a task adds its row, and the user removes the label and the row once reviewed.

## Phase 1 · Development
1. Take the first unblocked TODO (rework messages first). Mark it **In Progress** and **commit the backlog change alone**.
2. Develop with tests in the files you own.
3. **In doubt: spawn an Opus agent** (read-only consultant, `templates/design-consult-brief.md`), **decide**, and **write the decision** in the decision log. Never ask the user.
4. Run the tests, validation and verification, **the same steps the CI/CD pipeline runs** (from `WORKFLOW.md`/CI config), same order, until green.
5. Commit code + tests as work in progress (task stays In Progress).
6. `mailbox.sh send review <task> <msg>` (commit, changes, evidence, decisions, risks).

## Phase 2 · Review (Haiku)
Claim the oldest `review` message. Check criteria ↔ tests ↔ evidence (re-run the relevant tests), scope, decisions, leftovers.
- **Reject** → `mailbox.sh reject <msg> rework "<reasons>"`, one child subtask per distinct defect; the parent stays In Progress.
- **Accept** → mark the task **Done** with the backlog CLI (criteria/DoD checks, final summary with evidence), commit the backlog. If the task has **videos/journeys**, run or record them and make sure each has its description entry; failures go back as rework. Then `mailbox.sh send push <task> <msg>`.

## Phase 3 · Push (one worker)
- **When**: if the pipeline is slow and new pushes cancel running pipelines, push **only when the last pipeline has finished** (success or error). Otherwise push **as soon as possible**. Read CI state from the status file, never poll the CI API.
- **When a pipeline is red**: history `Green → Green → Red → Green2 → Green3` becomes `Green → Green → Red → Fix → Green2 → Green3` (the fix is inserted right after the red commit):
  1. Identify the red commit and the failing job/test.
  2. If it fails in CI but **not locally**, first **change or add a local test/setup that reproduces it** (parallelism, timing, environment, flags, load).
  3. Branch `fix/<red-sha>` from the red commit; the fix may be **test, code or pipeline**; verify locally.
  4. `insert-fix.sh <red> fix/<red> <integration-branch> --push` (rebase `--onto`, `--force-with-lease` under the push lock). This is the **only** allowed history rewrite; workers rebase afterwards.
  5. Wait for the new pipeline; repeat if red.
- Green → record the pipeline id on the task, `mailbox.sh send compare`.

Tension to know: Phase 2 marks Done **before** CI has seen the code. Phase 3 therefore adds the pipeline evidence, and a red pipeline that is attributable to a task reopens it (In Progress + note) until the fix is green.

## Phase 4 · Comparison
Compare the design reference with the actual implementation of the pushed commit (UI: pixel + typography + layout, seeded data, **data masked identically on both sides**, never tune data to the design). Write `reports/similarity/<date>-<task>.md` (score per screen/dimension, target, exact differences). When nothing is left to fix, add the `needs-review` label and the task's row in `NEEDS_REVIEW.md`. Every gap below the target becomes a **child subtask** (TODO) under the original task, which re-enters Phase 1; the original cannot finish until its children are Done.

## Mailbox protocol
- A mailbox is a directory `$STATE_DIR/mailbox/<box>/`; a message is a file `<epoch-ns>-<task>.md`, published atomically by rename. Boxes: `review`, `push`, `compare`, `rework`.
- **FIFO**: `claim` moves the oldest file into `processing/<worker>/` with `mv` (exactly one claimer wins); `done` archives it; `reject` re-queues it in another box with the reason on top.
- A crashed iteration leaves its message in `processing/<worker>/`: `ralph-loop.sh` re-queues unfinished messages at start.
- Messages are small: task id, branch+commit, evidence, decision ids, risks. Everything else is read from git and the backlog.

## Running the loops
```
AGENT_CMD="claude -p --model sonnet" scripts/ralph-loop.sh phase1 rework skills/mad-phase-1-development/prompt.md
AGENT_CMD="claude -p --model haiku"  scripts/ralph-loop.sh phase2 review skills/mad-phase-2-review/prompt.md
AGENT_CMD="claude -p"                scripts/ralph-loop.sh phase3 push   skills/mad-phase-3-push/prompt.md
AGENT_CMD="claude -p --model haiku"  scripts/ralph-loop.sh phase4 compare skills/mad-phase-4-comparison/prompt.md
```
Stop a loop with a `STOP` file in its state directory, or `STOP_WHEN_EMPTY=1`. Only one Phase 3 loop may run. Heavy commands go through `heavy.sh`.
