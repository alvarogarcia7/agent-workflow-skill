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

## Intake: every request becomes a task
Feature requests, bug reports and feedback are logged in the backlog **before** work starts (child of the closest task, parent reopened; quote the user; measurable criteria) and the task id is given back to the user. A requirement added to a task already in progress is added as a criterion (`--ac`) and sent to the agent working on it. The user's agents cannot talk to the user: the coordinator asks the questions (one batch, with a recommended default) and logs each answer as a decision.

## Lessons from long runs (CI, tests, credentials)
- **Two base URLs.** A CI job that runs Playwright against a Vite dev server has `BASE_URL` = the SPA; helpers that register users through the API need their own variable (`API_BASE_URL`) set in the job, or they get HTML back (`Unexpected token '<'`).
- **Test reports.** A pipeline's test-report tab shows only `artifacts:reports:junit`. Give every test run its own JUnit file (`PLAYWRIGHT_JUNIT_OUTPUT_FILE`) so a second run does not overwrite the first, and publish with a glob; check that the path really is written (a configured but never-written path shows nothing).
- **Flaky publish step.** When tests pass and only the last API call (release creation) fails with 5xx, do not rerun the whole job: have the script exit with a distinct code (75) for temporary failures and retry in a shell loop (for example 20 x 60 s); make the call idempotent (look the release up when a retry answers 409).
- **Credentials for CI.** Never copy a personal token into CI. Create a project access token with the smallest scope and role (for reading a repository: `read_repository`, Reporter) with an expiry, store it as a masked and hidden variable (`masked_and_hidden`), not protected when merge-request pipelines on unprotected branches need it, and document owner, scope and rotation date. Positive tests that need the secret skip with a clear message when it is absent, negative tests always run.
- **Rename jobs with care.** Job names are used by status scripts, docs and finalization notes; rename, update the docs and expect old pipelines to keep the old names.
- **A failed pipeline after a rename or journey change** is usually a spec reading removed UI or a stale build: rebuild the jar the e2e run uses after pulling backend changes before concluding a regression.
- **Shell traps.** zsh does not word-split `$var`; run test loops with `bash -c`. Never use `pkill -f`/`pgrep -f` (they match your own shell); keep PIDs.
- **Dirty main checkout.** If the coordinator's checkout holds the user's uncommitted edits, push coordinator commits from a separate worktree (cherry-pick, then `git reset --keep origin/<branch>` in the main checkout).

