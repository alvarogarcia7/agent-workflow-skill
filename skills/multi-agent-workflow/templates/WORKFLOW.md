# WORKFLOW.md (per-project settings for the multi-agent-workflow skill)

Copy to the repository root and fill in. Agents read this file; the skill itself stays project-independent.

## Verification recipe (CI-exact, in this order)
1. `<format check>`
2. `<lint / type check / static analysis>`
3. `<build>`
4. `<unit + integration tests for what you touched>`
5. `scripts/heavy.sh <UI / end-to-end command>` (at most 2 workers)

## Ports and base URLs (one row per agent)
| Agent | API port | UI port | Mock ports | Base-URL env vars to set (all of them) |
| ----- | -------- | ------- | ---------- | -------------------------------------- |
|       |          |         |            |                                        |

On non-default ports also set the backend's CORS origins and callback/frontend URLs. The end-to-end profile must raise login and public rate limits.

## Shared dependencies
How worktrees share installs (e.g. symlink `node_modules`, shared package cache): <fill in>.

## Definition of Done items (index used by `--check-dod N`)
1. <item>
2. <item>

## Task tracker
Backlog.md CLI. Validation command(s) before a push: `backlog doctor` and <project validator, if any>.
(Another tracker: map claim / note / check / finalize to its commands here.)

## Decision log
File: `DECISIONS.md`. Id blocks: agent <name> uses D-<from>..D-<to>.

## CI
Provider: <GitLab | GitHub>. Integration branch: <branch>. Merge request / PR: <id>. Details: `references/ci-gitlab.md` or `references/ci-github.md`.

## Owners
| Area | Owner (agent) | Files |
| ---- | ------------- | ----- |
