---
name: multi-agent-workflow
description: Run a large backlog with one coordinator plus parallel agents and subagents. Covers the Backlog.md CLI/MCP task loop, design-consult agents, decision log, file ownership and worktrees, local verification, a push and CI flow that never overloads CI, finalization with evidence, failing tests as child subtasks, and an optional design-parity loop. Use it when asked to orchestrate several agents on a milestone, to brief or supervise agents, to push or finalize tasks, or to run the parity loop.
---

# Multi-agent workflow

Implement a big backlog with one coordinator ("agent A") and several parallel agents. Follow it when you coordinate, and when you are an agent that was briefed with it. It works for any codebase: the project-specific parts (verification commands, ports, test tools) live in your **brief** and in a short `WORKFLOW.md` in the repository, not here.

## 0. Ground rules (always)

1. **The backlog is the source of truth for tasks.** With [Backlog.md](https://github.com/MrLesk/Backlog.md): run `backlog instructions overview` once per conversation; read `backlog instructions task-creation`, `task-execution` and `task-finalization` before creating tasks, starting/changing status, or ticking criteria. **Never edit the task files directly: use the `backlog` CLI (or its MCP tools)** so metadata, links and history stay consistent. Validate the backlog before you push.
2. **Do not touch tasks that someone else started or owns.** List them for the coordinator instead.
3. **Do not ask the user product/design questions** while working a milestone loop. Settle ambiguities yourself (section 3), log the decision, and flag it in your report.
4. **A parent task can only be finished when all its children are Done.** Failing tests, screenshot/design differences, user-reported bugs and parity gaps become **child subtasks** of the original task (`backlog task create "<title>" -p <parent-id> -m <milestone> -d "<what is wrong vs expected>" --ac "<criterion>"`). Move an already-Done original back to `In Progress` with a note (`--append-notes`) until its children are Done.
5. **Every user-facing task gets a happy-path end-to-end walkthrough** (section 5), if the project records them.
6. **Report faithfully.** Failing tests, skipped steps and unverified claims are stated as such. "Done" needs evidence: spec/test names, a green pipeline id.

**Helper scripts** (in `scripts/`; configuration in `scripts/env.example`): `safe-push.sh`, `ci-trigger.sh`, `heavy.sh`, `keep-both.py`. Copy them to a path every agent can read; they keep shared state (locks, `ci-status.json`, logs, queue file) in `STATE_DIR`.

## 1. Roles

| Role                      | Does                                                                                                                 | Typical model     |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------- | ----------------- |
| Coordinator (agent A)     | Owns the queue, design decisions, integration pushes, finalization, user communication                               | the session model |
| Design consultant         | Read-only agent that reads the decision log, decision records, tasks and code, and returns numbered decisions + a work split | Opus              |
| Backend/API worker        | Schema, entities, services, controllers, API request files, server tests                                             | Haiku             |
| Frontend worker           | Screens, components, UI specs, walkthroughs                                                                          | Haiku             |
| Integrations/audit worker | Third-party integrations, audit/logging, mocks on fixed ports                                                        | Opus              |
| Parity workers            | Design parity per screen shard, measurement                                                                          | Haiku             |
| CI agent                  | Runs `ci-trigger.sh`, writes failure reports                                                                         | Haiku             |

Pick models by risk: cheap models for well-specified tasks with strong verification, a stronger model for design consults, integrations and anything ambiguous. Spawn agents with the Agent tool. **Brief them like peers** (template: `templates/agent-brief.md`): goal, what is already decided (decision ids), files they own and must not edit, the verification recipe, push rules, ports, how to report. A brief is the only context they get. Resume an idle agent with SendMessage (a new Agent call loses its context). Run independent agents in parallel; do not duplicate an agent's work yourself.

## 2. Work loop per task

1. Search the backlog (`backlog task search`, `task view <id> --plain`); check remote branches and the decision log for an existing implementation.
2. If the design is ambiguous or crosses subsystems, run a **design consult** first (section 3).
3. Claim the task: `backlog task edit <id> -a @agent-x -s "In Progress"`. Implement within your owned files.
4. Write the tests that prove the acceptance criteria: unit/integration, UI/end-to-end, request files for new endpoints, a walkthrough for UI tasks.
5. Verify **locally** (section 6). Commit with the task id in the message (`TASK-14.05: Add case to plan`).
6. Push (section 7). Immediately start the next task; do not wait for CI.
7. When a pipeline that contains your commits is green: tick the criteria and Definition of Done with evidence, write the final summary, set `Done` (section 8). Reword criteria that decisions superseded, with the reason in the notes.

## 3. Decisions (decision log)

- Keep one append-only log (`DECISIONS.md`). Entry: `**D-nn · task · decider** — decision. *Why:* reason. *Alternatives:* …` (template: `templates/decision-entry.md`). Give each agent its own number block to avoid collisions; on a merge conflict in the log keep both sides (`scripts/keep-both.py DECISIONS.md`).
- **Design consult**: spawn an Opus agent, read-only ("do not edit files, do not run servers"), with the tasks, existing code and decision records. Ask for concrete decisions (data model, endpoints, rules, edge cases), the contradictions between task criteria, and a split into streams with file ownership. Record the answer in the log, then brief the workers.
- A conflict with a team decision record (an ADR) is reconciled in a new log entry ("X is working state; the commit to Y is a later step") and flagged to its owner. Do not silently contradict it.

## 4. Splitting work between agents

- **One owner per file group.** Shared files get a single mount line, rebased carefully. Schema/migration files are edited only by the agent doing "Step 0", pushed alone, then frozen.
- **Contract first**: the backend agent pushes migrations, endpoints, request files and the typed client early; the frontend agent builds on them.
- **Each agent has its own git worktree** (`git worktree add <path>/agent-x -b agent-x origin/<branch>`), its **own ports**, and kills only its own servers **by PID**. Never `pkill -f`: it matches your own shell's command line.
- A stale running backend is a classic trap ("not found" for an endpoint that exists in code): restart your server after pulling backend changes.
- Idle agents get real work: verification runs, missing tests, finalization prep, review.

## 5. End-to-end walkthroughs (optional, recommended for UI work)

One happy-path walkthrough per user-facing task, recorded as a video/test with captions, kept next to a short human description (release notes). Rules that avoid flakiness: wait for the screen before interacting; never tap an element right after navigation without waiting; use retrying helpers for elements that re-render; give each walkthrough its own workspace/data.

## 6. Local verification (before every push)

Define the recipe once in `WORKFLOW.md` and put it in every brief. Shape:

1. Build and static checks that CI runs (formatter check, linter, type check, static analysis such as SpotBugs), **in the same order and with the same flags as CI**.
2. Unit and integration tests for what you touched; request files for new endpoints.
3. UI/end-to-end tests for the area, on **your own ports**, through the limiter: `scripts/heavy.sh <command>` with at most 2 workers.
4. Every test that creates or deletes data uses a **private workspace/dataset**; a shared seed dataset stays read-only.
5. Fixed-port mocks (identity provider, git forge, issue tracker) keep their tests serial.

Shared-machine hygiene: run heavy commands only through `heavy.sh`; stop servers when idle; delete test outputs, videos, build output and screenshots after runs (disks fill); set every base-URL environment variable your test helpers use when running on non-default ports (a helper that defaults to another agent's port silently tests the wrong backend).

## 7. Push and CI flow (one pipeline at a time)

CI collapses when many agents push often: every push cancels the running pipeline and none completes. So:

- **Push every locally verified commit immediately** with `scripts/safe-push.sh`: it takes a lock, rebases only if behind, and pushes with `-o ci.skip`, so the push starts **no** pipeline. Never plain `git push`, never force.
- **One CI agent** runs `scripts/ci-trigger.sh` (exactly one instance): every few minutes, if no pipeline is active and the head is not covered by a **non-skipped** pipeline, it creates one pipeline for the head via the API, writes `ci-status.json`, and appends failures to `ci-failures.log`.
- **Agents never poll the CI API** (it rate-limits with HTTP 429): read `ci-status.json` at most every 5 minutes, and check that your commit is in a green pipeline with `git merge-base --is-ancestor <commit> <last_pipeline.sha>` and `last_pipeline.status == success`.
- A failed pipeline: the CI agent writes a report (failed job, tests, classification); the coordinator routes it to the owner. A failure that repeats on every attempt is a bug, not a flake.
- **Batch integration**: when several agents hold local commits, the coordinator may merge their branches into one, resolve duplicates, run the full checks once, and push once.
- Commits that only touch backlog/docs create "skipped" pipelines; they are not verification.

## 8. Finalization

1. A green pipeline that contains the commits (see above).
2. Per task, with the CLI: reword criteria superseded by decisions (`--acceptance-criteria` with the full list keeps checks for unchanged text), `--check-ac N`, `--check-dod N`, `--append-notes` with the evidence, `--final-summary`, `-s Done`.
3. Parents last, only when every child reads Done. Re-validate the backlog.
4. Never claim evidence for code that is not in a green pipeline: reopen the task instead. A finalization script that edits many tasks must run from the checkout you will commit from, support `--dry-run`, and be idempotent.

## 9. Failing tests and bug reports → child subtasks

For a failing test or a user-reported bug: open the screenshot/error context, describe what is on screen vs expected, classify it (test out of date / real regression / environment or port problem / load flake: flakes get no subtask), find the original task, create the child with the difference as the description and "the test passes and the difference is gone" as the criteria, reopen the original, fix, and mark the child Done with evidence.

## 10. Design-parity loop (optional)

Goal: every screen reaches a target similarity (for example 95%: pixel + typography + layout, **data excluded**) against a design reference, measured by a script on a seeded dataset. Workers claim an unassigned open parity child of their screen shard, copy the design's actual CSS/DOM values (never approximate), keep every test id, re-measure through `heavy.sh`, and close the child with the measured evidence. Measurement changes must be principled and logged: data rows (list/table rows, activity entries, chart bars) are masked identically on both sides, and seed values are never tuned to the design. Findings go back into the child tasks' notes so any worker can pick them up cold.

## 11. Coordinator checklist

- Keep a queue file (priorities, owners, ports) in `STATE_DIR` and update it after each batch (`templates/queue.md`).
- One instruction per message; confirm who is idle and give them work.
- Watch machine load, disk and CI rate limits; kill stray pollers by PID; announce rule changes to all agents at once.
- Decide quickly what is yours to decide; log it; report only what the user needs.
- Never leave a claim in the backlog that the code and a green pipeline do not back.

## Lessons learned (anti-patterns)

- Many agents each polling CI in a loop caused 429s and blind spots: poll one file instead.
- Parallel browser tests on a shared machine crash ("Target crashed"): cap concurrency with a limiter.
- Tests that delete from a shared seed dataset flake when run in parallel: private datasets.
- A "skipped" pipeline for the head made the trigger think CI had run: only non-skipped pipelines count.
- A helper whose base URL defaults to another agent's port makes tests pass or fail for the wrong reason.
- Hard-coded process matching (`pkill -f <name>`) can kill your own shell: kill by PID.
- Superseded acceptance criteria left unticked block parents forever: reword them in the CLI with the reason.
