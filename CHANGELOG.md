# Changelog

## 0.1.0
- Initial generic skill: SKILL.md playbook, templates, scripts.
- `scripts/lib.sh`: env discovery through the git common dir, locks (flock or mkdir fallback), numeric validation.
- `safe-push.sh`: `BRANCH` required, `PUSH_OPTS` (default `-o ci.skip`), clean-tree check, lock, optional `POST_REBASE_CHECK`, "remote moved" message.
- `heavy.sh`: lock not leaked to the job, usage check, mkdir fallback, numeric `HEAVY_SLOTS`.
- `ci-trigger.sh`: per-head trigger marker (merged-results safe), trigger failure detection and `trigger_error`, `canceling`/`waiting_for_callback` active, atomic UTC status file, exponential backoff.
- `keep-both.py`: diff3/zdiff3 safe, blank line between sides, duplicate decision id report, non-zero exit on leftover markers.
- References (GitLab, GitHub, parity loop, lessons), templates (WORKFLOW, finalize, handover, design consult, CI report).
- Test suite with a fake `glab`.

## Unreleased
- Rule: every request becomes a backlog task first (SKILL.md section 0, intake in the phase pipeline); lessons from long CI runs (base URLs, JUnit reports, publish retry loop, scoped CI tokens).
- Four phase skills and `MULTI_AGENT_DEV_SKILL.md`; `mailbox.sh`, `ralph-loop.sh`, `insert-fix.sh`.
