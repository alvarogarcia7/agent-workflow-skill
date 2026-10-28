# Lessons learned and operating rules

## Anti-patterns
- Many agents polling CI in a loop caused 429s and blind spots: poll one file.
- Parallel browser tests on a shared machine crash ("Target crashed"): cap concurrency with `heavy.sh`; one heavy end-to-end run per agent.
- Tests that delete from a shared seed dataset flake in parallel: private datasets.
- A "skipped" pipeline for the head made the trigger think CI had run: only non-skipped pipelines count.
- A helper whose base URL defaults to another agent's port tests the wrong backend: set every base-URL variable.
- `pkill -f <name>` can kill your own shell: kill by PID.
- Superseded acceptance criteria left unticked block parents forever: reword them with the reason.
- A stale running backend gives "not found" for endpoints that exist in code: restart after pulling backend changes.

## Environment
- Share dependency installs across worktrees (symlink `node_modules` or use a shared cache), or disk and time blow up.
- On non-default ports also set the backend's CORS origins and the callback/frontend URLs.
- The end-to-end profile raises login and public rate limits.
- Delete test outputs, videos, build output and screenshots after runs.
- Commit attribution follows the repository's rules.

## Handover
Before an agent stops it appends to the task notes (`templates/handover.md`): branch, last commit, verification state, ports to free, next step. A new agent starts from those notes.

## Claim races
The coordinator assigns tasks. Agents claim only what the queue gives them and re-read the task after claiming (assignee and status) before starting.

## Verify agent reports
Confident summaries are not evidence. Before finalizing, the coordinator spot-checks: the named tests exist, the commit is in the green pipeline.

## Cost control
At most N concurrent agents. Stop idle agents instead of leaving them polling. Fast models only with strong verification. Design consults stay read-only with a narrow brief. Do not respawn: resume with SendMessage.

## Stuck agents
No report within X minutes: ask once, then reassign and free its ports and worktree.

## Cleanup
After merge: `git worktree remove <path>`, delete the agent branch, stop its servers by PID, delete scratch output.

## What the coordinator reports to the user
Done tasks with pipeline ids; decisions taken (ids) the user may want to revisit; failures and their owners; blocked items. Nothing else.

## Design consult output format
Numbered decisions; contradictions between criteria; streams with file ownership; open risks (`templates/design-consult-brief.md`).

## Finalization script
`templates/finalize.sh`: `--dry-run`, idempotent, prints quoted commands, per-command failure message, children-Done check before parents. Run it from the checkout you will commit from.
