---
name: multi-agent-workflow
description: Coordinate one coordinator plus parallel Claude Code agents/subagents on a Backlog.md backlog; briefing and supervising agents, design consults, decision log, file ownership and worktrees, local verification, CI-safe pushing (one pipeline at a time), evidence-based finalization. Use when the user asks to orchestrate or parallelize agents over backlog tasks or a milestone, or in a repository that has .agent-workflow.env / WORKFLOW.md. Not for a single ordinary git push or one-off task.
---

# Multi-agent workflow

One coordinator ("agent A") and several parallel agents implement a big backlog. Follow it as coordinator or as a briefed agent. Project specifics (verification commands, ports, test tools) live in your **brief** and in `WORKFLOW.md` (template: `templates/WORKFLOW.md`).

**Requirements and assumptions**: Claude Code (Agent/SendMessage tools), Backlog.md >= 1.x (CLI or MCP), git worktrees, GitLab MR pipelines for the CI loop. Without Backlog.md, map the task commands to your tracker in `WORKFLOW.md`; without GitLab, see `references/ci-github.md`. Scripts: `bash`, `git`, `python3`, `flock` (macOS: `brew install flock`, or mkdir fallback).

## 0. Ground rules

1. **The backlog is the source of truth.** Run `backlog instructions overview` once per conversation; read `backlog instructions task-creation`, `task-execution`, `task-finalization` before creating tasks, changing status or ticking criteria. **Never edit task files directly: use the `backlog` CLI (or MCP).** Before a push run `backlog doctor` (and the validator `WORKFLOW.md` names, if any).
2. **Every request becomes a task first.** Whenever the user (or anyone) asks for a new feature, a change, a bug fix or sends feedback, search the backlog (`backlog search`), then create or extend a task with the CLI **before any work starts**: a child of the closest existing task when it belongs to one (reopen a Done parent), otherwise a new task; with a description (wrong vs expected, or the goal), measurable acceptance criteria and the user's wording quoted. Tell the user the task id. Work that has no task is not done: it cannot be assigned, verified or finalized. User feedback and added requirements to a running task are added as acceptance criteria on that task (`--ac`) and sent to the agent working on it.
3. **No review gates before implementation.** Refinement (design notes, options, defaults, child drafts) is done by an agent, the open questions are put to the user once in one batch with a recommended default each, the answers are recorded as decisions, and the work then goes straight to a worker: the user is not asked to approve a document before implementation starts. If the user has already read the refinement, or says to go ahead, implementation starts at once. The user reviews **implemented solutions**: when a task or epic is implemented and verified it gets the label `needs-review` (`backlog task edit <id> --add-label needs-review`; list with `backlog task list --labels needs-review --plain`), and the coordinator's report ends with that review list (what to look at, where to run it, what was decided for the user). The user's review feedback becomes new tasks (rule 2) or criteria; removing the label means reviewed. Hard-to-reverse or outward-facing actions (publishing, deleting, spending money, writing to someone else's repository) still need the user's go-ahead.
4. Do not touch tasks someone else started or owns; list them for the coordinator (unless the user releases them).
5. Do not ask the user product/design questions in a milestone loop: decide (section 3), log it, flag it in the report.
6. **A parent is finished only when all children are Done.** Failing tests, design differences, bug reports become **child subtasks** (`backlog task create "<title>" -p <parent> -m <milestone> -d "<wrong vs expected>" --ac "<criterion>"`). Move a Done original back to `In Progress` with `--append-notes` until its children are Done.
7. Every user-facing task gets a happy-path walkthrough (section 5) if the project records them.
8. **Report faithfully.** Failing tests, skipped steps and unverified claims are stated as such. "Done" needs evidence: test names, a green pipeline id.

Scripts (`scripts/`, config `scripts/env.example`, shared state in `STATE_DIR`): `safe-push.sh`, `ci-trigger.sh`, `heavy.sh`, `keep-both.py`, `lib.sh`.

## 1. Roles

| Role                  | Does                                                                 | Model                  |
| --------------------- | -------------------------------------------------------------------- | ---------------------- |
| Coordinator           | Queue, decisions, integration pushes, finalization, user reports     | the session model      |
| Design consultant     | Read-only: returns numbered decisions + work split                   | strong (e.g. Opus)     |
| Backend / frontend / parity workers | Well-specified tasks with strong verification          | fast (e.g. Haiku)      |
| Integrations / audit worker | Third-party integrations, mocks, anything ambiguous            | strong                 |
| CI agent              | Runs `ci-trigger.sh`, writes `ci-report-<pipeline>.md`               | fast                   |

Brief agents like peers (`templates/agent-brief.md`): goal, decisions (ids), owned and forbidden files, verification recipe, push rules, ports, report format. The brief is all they get. Resume idle agents with SendMessage; do not duplicate their work.

## 2. Work loop per task

1. Search: `backlog search "<query>" --plain`, `backlog task view <id> --plain`; check remote branches and the decision log.
2. Ambiguous or cross-cutting: design consult first (section 3).
3. Claim only what the queue assigns: `backlog task edit <id> -a @agent-x -s "In Progress"`, then re-read the task. Implement in your files.
4. Write tests proving the criteria (unit, UI/e2e, request files, walkthrough).
5. Verify locally (section 6). Commit with the task id.
6. Push (section 7), start the next task, do not wait for CI.
7. When a green pipeline contains your commits: finalize (section 8). Before stopping, leave a handover (`templates/handover.md`).

## 3. Decisions

- One append-only log (`DECISIONS.md`), entry format `templates/decision-entry.md`, one id block per agent. On merge conflicts run `scripts/keep-both.py DECISIONS.md` (reports duplicate ids, non-zero if markers remain).
- **Design consult**: strong model, read-only, brief `templates/design-consult-brief.md` (output: decisions, contradictions, streams with ownership, risks). Log the answer, then brief workers.
- A conflict with a team decision record is reconciled in a new log entry and flagged to its owner, never silently contradicted.

## 4. Splitting work

- One owner per file group; schema/migrations edited by one agent ("Step 0"), pushed alone, then frozen. Contract first (migrations, endpoints, typed client), UI builds on it.
- Each agent: own worktree (`git worktree add <path>/agent-x -b agent-x origin/<branch>`), own ports, kills only its own servers **by PID** (never `pkill -f`). Share dependency installs across worktrees.
- Restart your server after pulling backend changes. Give idle agents real work.

## 5. Walkthroughs (optional, for UI work)

One happy-path walkthrough per user-facing task, recorded as video/test with captions (needs a test runner that records video). Wait for the screen before interacting, use retrying helpers, use a private workspace per walkthrough.

## 6. Local verification (before every push)

Recipe in `WORKFLOW.md`: CI-exact checks in CI order (formatter, linter, type check, static analysis such as SpotBugs, ESLint, mypy), tests for what you touched, UI/e2e on your own ports via `scripts/heavy.sh <cmd>` (max 2 workers), private datasets for tests that write, serial tests for fixed-port mocks. Set every base-URL variable, plus CORS/frontend URLs on non-default ports; the e2e profile raises rate limits. Clean test output afterwards. More: `references/lessons.md`.

## 7. Push and CI (one pipeline at a time)

- Push each verified commit with `scripts/safe-push.sh` (lock, clean-tree check, rebase if behind, `PUSH_OPTS` default `-o ci.skip`, `BRANCH` required). A rebased push is **not re-verified**; set `POST_REBASE_CHECK` for a quick check. Never plain `git push`, never force.
- One CI agent runs `scripts/ci-trigger.sh`: at most one pipeline per MR head, writes `ci-status.json` (schema, merged-results caveat, permissions: `references/ci-gitlab.md`).
- Agents never poll the CI API. Read `ci-status.json` at most every 5 minutes. **If `updated` is older than 3 intervals, or `error`/`trigger_error` persists, tell the coordinator: the CI loop is dead.**
- Green means `last_pipeline.status == success` and your commit is an ancestor of `last_pipeline.mr_head` (or `sha`).
- Failure: CI agent writes `templates/ci-report.md`; coordinator routes it. A repeating failure is a bug. Skipped pipelines are not verification.
- Batch integration: the coordinator may merge branches, run full checks once, push once.

## 8. Finalization

1. Green pipeline containing the commits.
2. Per task: reword superseded criteria (`--acceptance-criteria` replaces all criteria; matching trimmed text keeps checks; see `backlog task edit --help`), `--check-ac N`, `--check-dod N` (DoD indexes in `WORKFLOW.md`), `--append-notes` evidence, `--final-summary`, `-s Done`.
3. Parents last, only when every child is Done. Run `backlog doctor`.
4. **Verify agent reports** (test names exist, commit in the pipeline) before finalizing. Never claim evidence for code not in a green pipeline: reopen. Batch script: `templates/finalize.sh` (dry-run, idempotent, children check).

## 9. Failing tests and bug reports

Open the screenshot/error, describe screen vs expected, classify (test out of date / regression / environment or port / load flake: no subtask), find the original task, create the child with the difference and "test passes, difference gone" as criteria, reopen the original, fix, close the child with evidence.

## 10. Coordinator checklist

- Queue file in `STATE_DIR` (`templates/queue.md`); one instruction per message; keep agents busy; announce rule changes to all.
- Watch load, disk, rate limits; stop idle agents; ask a silent agent once, then reassign and free its ports and worktree.
- Cleanup after merge: `git worktree remove`, delete branches.
- Report to the user: done tasks with pipeline ids, decisions taken (ids), failures and owners, blocked items. Nothing else.
- Cost control, claim races, handover: `references/lessons.md`. Optional design-parity loop: `references/parity-loop.md`.
