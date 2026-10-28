#!/usr/bin/env bash
# Push the current branch to the shared integration branch WITHOUT starting a CI pipeline (default push option
# "-o ci.skip", GitLab). A single CI trigger (ci-trigger.sh) creates at most one pipeline for the newest head, so many
# agents can push often. Run it from your worktree after your local checks passed and your work is committed.
# Exit 0 pushed | 3 lock busy (retry) | 1 rebase/check/push problem | 2 bad configuration.
# Config (env file, see env.example): BRANCH (REQUIRED, no default), REMOTE, STATE_DIR,
#   PUSH_OPTS       push options; default "-o ci.skip". Set PUSH_OPTS="" on remotes without push options (GitHub).
#   POST_REBASE_CHECK  optional command run (via sh -c) after a rebase and before the push; non-zero aborts the push.
#                      A rebased commit was verified only before the rebase; use this to re-run a quick check.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
aw_load_env; aw_defaults
: "${BRANCH:?set BRANCH (the shared integration branch) in the env file}"
PUSH_OPTS="${PUSH_OPTS--o ci.skip}"
if ! { git diff --quiet && git diff --cached --quiet; }; then
  echo "uncommitted changes in tracked files: commit or discard them first (a rebase would fail)"; exit 1
fi
aw_lock push 60 || { echo "lock busy: another agent is pushing"; exit 3; }
git fetch -q "$REMOTE" "$BRANCH" || { echo "fetch failed"; exit 1; }
if [ "$(git rev-list --count "HEAD..$REMOTE/$BRANCH")" != "0" ]; then
  git pull --rebase "$REMOTE" "$BRANCH" || { echo "rebase failed: resolve it (or git rebase --abort), re-run your checks, retry"; exit 1; }
  if [ -n "${POST_REBASE_CHECK:-}" ]; then
    sh -c "$POST_REBASE_CHECK" || { echo "POST_REBASE_CHECK failed after rebase: not pushing"; exit 1; }
  fi
fi
# shellcheck disable=SC2086
if ! git push $PUSH_OPTS "$REMOTE" "HEAD:$BRANCH"; then
  git fetch -q "$REMOTE" "$BRANCH" 2>/dev/null
  if [ "$(git rev-list --count "HEAD..$REMOTE/$BRANCH" 2>/dev/null)" != "0" ]; then
    echo "push failed: the remote moved (someone pushed in between); re-run safe-push.sh"
  else
    echo "push failed (see the git message above; a remote without push-option support needs PUSH_OPTS=\"\")"
  fi
  exit 1
fi
echo "pushed${PUSH_OPTS:+ (options: $PUSH_OPTS)}: $(git log -1 --oneline)"
