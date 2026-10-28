# CI on GitHub Actions

The scripts target GitLab out of the box. On GitHub:

1. Workflow `on:` should be `workflow_dispatch` (add `pull_request` only if you accept one run per push) and add
   `concurrency: {group: integration, cancel-in-progress: false}` so runs queue instead of cancelling.
2. Set `PUSH_OPTS=""` in the env file: `-o ci.skip` does nothing on GitHub (and remotes without push-option support reject the push).
   `[skip ci]` in commit messages is an alternative, but it must be in every pushed head commit.
3. There is no "create MR pipeline" endpoint: trigger with `gh workflow run`.
4. The token needs permission to run workflows (`actions: write` / `workflow` scope).

## Trigger sketch (replace the glab calls in ci-trigger.sh)
```bash
WF=ci.yml
head=$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)
runs=$(gh run list --workflow "$WF" --branch "$BRANCH" --limit 20 --json databaseId,status,conclusion,headSha)
# active = status in queued, in_progress, waiting, pending, requested
active=$(jq '[.[]|select(.status!="completed")]|length' <<<"$runs")
last=$(jq '[.[]|select(.conclusion!="skipped")][0] // {}' <<<"$runs")
lsha=$(jq -r '.headSha // ""' <<<"$last")
mark="$STATE_DIR/.triggered-$head"
if [ "$active" = 0 ] && [ -n "$head" ] && [ "$lsha" != "$head" ] && [ ! -f "$mark" ]; then
  if gh workflow run "$WF" --ref "$BRANCH"; then echo triggered > "$mark"; else trigger_error="gh workflow run failed"; fi
fi
# failed jobs of run $id: gh run view "$id" --json jobs --jq '.jobs[]|select(.conclusion=="failure")|.name'
```
Write the same `ci-status.json` schema (see ci-gitlab.md) so agents read one format. Keep the marker, the backoff and the atomic write from `ci-trigger.sh`.
