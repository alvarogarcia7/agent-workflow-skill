#!/usr/bin/env bash
# Run a HEAVY command (browser tests, full builds, benchmarks) under a machine-wide limit of N concurrent jobs, so that
# several agents sharing one machine do not oversubscribe the CPU/RAM (symptoms: browser crashes, timeouts, 429s).
# Usage: heavy.sh <command> [args...]      Config: HEAVY_SLOTS (default 2), STATE_DIR.
ENV_FILE="${AGENT_WORKFLOW_ENV:-.agent-workflow.env}"; [ -f "$ENV_FILE" ] && . "$ENV_FILE"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/agent-workflow}"; SLOTS="${HEAVY_SLOTS:-2}"
DIR="$STATE_DIR/heavy"; mkdir -p "$DIR"
n=0
while true; do
  for s in $(seq 1 "$SLOTS"); do
    exec 9>"$DIR/slot$s"
    if flock -n 9; then
      echo "heavy slot $s acquired: $*" >&2
      "$@"; rc=$?
      exec 9>&-
      exit $rc
    fi
    exec 9>&-
  done
  n=$((n+1)); [ $((n % 6)) = 1 ] && echo "waiting for a heavy slot ($(date +%T))" >&2
  sleep 10
done
