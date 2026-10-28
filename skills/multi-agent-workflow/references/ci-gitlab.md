# CI on GitLab (merge-request pipelines)

## Flow
Agents push with `safe-push.sh` (`-o ci.skip`): no pipeline starts. One CI agent runs `scripts/ci-trigger.sh`; each cycle it creates at most one pipeline for the MR head and writes `ci-status.json`.

## Permissions
Creating MR pipelines needs a token with `api` scope and the Developer role (plus push/merge rights if the source branch is protected). `.gitlab-ci.yml` must define jobs for `merge_request_event`; otherwise the POST returns 400 "No stages / jobs" or 403. A failed trigger lands in `trigger_error` and is retried with backoff.

## Merged results / merge trains
The pipeline `sha` is a merge-ref commit, not the MR head, and is not fetched locally, so `git merge-base --is-ancestor <commit> <last_pipeline.sha>` fails. Use `last_pipeline.mr_head` (the head the pipeline was triggered for) instead. The per-head marker `.triggered-<head>` (content: pipeline id) stops a new pipeline every cycle. A failed pipeline is not re-triggered for the same head; delete the marker to force a re-run.

## ci-status.json
```
{"updated": "2025-01-01T12:00:00Z",   // UTC, written atomically
 "interval": 180,                      // TRIGGER_INTERVAL
 "error": null,                        // API/read error of the last cycle, else null
 "trigger_error": null,                // last failed trigger (403, 400, 429...), else null
 "mr_head": "<sha>", "active_pipelines": 0,
 "last_pipeline": {"id": 1, "status": "success|failed|running|none", "sha": "<sha>",
                   "mr_head": "<sha or null>", "jobs": {"<job name>": "<status>"}}}
```
Staleness rule: if `updated` is older than 3 * `interval`, the CI loop is dead: tell the coordinator. If `error` or `trigger_error` is set for several cycles, tell the coordinator too.
Green check for a commit C: `last_pipeline.status == "success"` and C is an ancestor of `last_pipeline.mr_head` (or of `sha` without merged results).

## Rules
- "active" statuses: created, waiting_for_resource, preparing, waiting_for_callback, pending, running, canceling, scheduled.
- Skipped pipelines (docs-only commits) are not verification.
- Agents never poll the API (HTTP 429); read the file at most every 5 minutes.
- CI agent failure reports: `templates/ci-report.md` saved as `$STATE_DIR/ci-report-<pipeline>.md`.
