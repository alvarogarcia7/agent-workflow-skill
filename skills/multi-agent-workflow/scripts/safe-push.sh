#!/usr/bin/env bash
# Push the current branch to the shared integration branch WITHOUT starting a CI pipeline (push option ci.skip).
# A single CI trigger (ci-trigger.sh) creates at most one pipeline for the newest head, so many agents can push often.
# Run it from your worktree after your local checks passed and your work is committed.
# Exit 0 pushed | 3 lock busy (retry in a few seconds) | 1 rebase/push problem.
# Config: see env.example (STATE_DIR, REMOTE, BRANCH).
set -u
ENV_FILE="${AGENT_WORKFLOW_ENV:-.agent-workflow.env}"; [ -f "$ENV_FILE" ] && . "$ENV_FILE"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/agent-workflow}"; REMOTE="${REMOTE:-origin}"; BRANCH="${BRANCH:-main}"
mkdir -p "$STATE_DIR"; LOCK="$STATE_DIR/push.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  # a lock older than 5 minutes is stale
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || { echo "lock busy"; exit 3; }
  else echo "lock busy: another agent is pushing"; exit 3; fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
git fetch -q "$REMOTE" "$BRANCH" || { echo "fetch failed"; exit 1; }
if [ "$(git rev-list --count "HEAD..$REMOTE/$BRANCH")" != "0" ]; then
  git pull --rebase "$REMOTE" "$BRANCH" || { echo "rebase failed: resolve it (or git rebase --abort), re-run your checks, retry"; exit 1; }
fi
git push -o ci.skip "$REMOTE" "HEAD:$BRANCH" || { echo "push failed"; exit 1; }
echo "pushed (ci skipped): $(git log -1 --oneline)"
