#!/usr/bin/env bash
# Shared helpers for the multi-agent-workflow scripts. Source it:  . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# Provides: aw_load_env, aw_defaults, aw_require_uint, aw_have_flock, aw_lock, aw_utc.

# Load the env file. Search order: $AGENT_WORKFLOW_ENV (use an ABSOLUTE path), else <main checkout>/.agent-workflow.env,
# found through the git COMMON dir, so every `git worktree` of the repository sees the same file. The current directory
# is deliberately not searched (a file there would be sourced as code, and it does not exist in other worktrees).
aw_load_env() {
  local f="${AGENT_WORKFLOW_ENV:-}" common
  if [ -z "$f" ]; then
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && f="$(dirname "$common")/.agent-workflow.env"
  fi
  if [ -n "$f" ] && [ -f "$f" ]; then
    # shellcheck disable=SC1090
    . "$f"; AW_ENV_FILE="$f"
  elif [ -n "${AGENT_WORKFLOW_ENV:-}" ]; then
    echo "warning: AGENT_WORKFLOW_ENV=$AGENT_WORKFLOW_ENV does not exist" >&2
  fi
}

# Defaults that are safe everywhere. BRANCH has NO default on purpose: pushing somewhere by accident is worse than failing.
aw_defaults() {
  STATE_DIR="${STATE_DIR:-$HOME/.local/state/agent-workflow}"
  REMOTE="${REMOTE:-origin}"
  mkdir -p "$STATE_DIR"
}

# aw_require_uint NAME VALUE : exit 2 unless VALUE is a positive integer.
aw_require_uint() {
  case "$2" in ''|*[!0-9]*|0) echo "error: $1 must be a positive integer, got '$2'" >&2; exit 2;; esac
}

# flock exists on Linux (util-linux); macOS needs `brew install flock`. AW_NO_FLOCK=1 forces the mkdir fallback (tests).
aw_have_flock() { [ -z "${AW_NO_FLOCK:-}" ] && command -v flock >/dev/null 2>&1; }

# aw_lock NAME [TIMEOUT_SECONDS]: take the exclusive lock $STATE_DIR/NAME.lock for the rest of the process.
# Returns 3 on timeout. With flock the lock dies with the process (no stale locks). The fallback is mkdir plus a pid
# file; a lock whose pid is dead is taken over (best effort: two takers racing on the same stale lock can still collide).
aw_lock() {
  local name="$1" to="${2:-60}" waited=0 d p
  if aw_have_flock; then
    exec 8>"$STATE_DIR/$name.lock" || return 1
    flock -w "$to" 8 || return 3
    return 0
  fi
  d="$STATE_DIR/$name.lock.d"
  until mkdir "$d" 2>/dev/null; do
    p=$(cat "$d/pid" 2>/dev/null)
    if { [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; } || { [ -z "$p" ] && [ -n "$(find "$d" -maxdepth 0 -mmin +10 2>/dev/null)" ]; }; then
      rm -rf "$d"; continue
    fi
    [ "$waited" -ge "$to" ] && return 3
    sleep 1; waited=$((waited + 1))
  done
  echo $$ >"$d/pid"
  AW_LOCKDIR="$d"; trap 'rm -rf "$AW_LOCKDIR"' EXIT
}

aw_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
