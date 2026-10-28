#!/usr/bin/env bash
# Run a HEAVY command (browser tests, full builds, benchmarks) under a machine-wide limit of N concurrent jobs, so that
# several agents sharing one machine do not oversubscribe the CPU/RAM (symptoms: browser crashes, timeouts, 429s).
# Usage: heavy.sh <command> [args...]
# Config: HEAVY_SLOTS (default 2, positive integer), HEAVY_POLL (seconds between attempts, default 10), STATE_DIR.
# Uses flock; without flock (macOS: `brew install flock`) it falls back to mkdir slots with a pid file.
# The lock is NOT inherited by the command: a background server it leaves running does not hold the slot.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ $# -gt 0 ] || { echo "usage: heavy.sh <command> [args...]" >&2; exit 2; }
aw_load_env; aw_defaults
SLOTS="${HEAVY_SLOTS:-2}"; POLL="${HEAVY_POLL:-10}"
aw_require_uint HEAVY_SLOTS "$SLOTS"; aw_require_uint HEAVY_POLL "$POLL"
DIR="$STATE_DIR/heavy"; mkdir -p "$DIR"
n=0
while true; do
  for s in $(seq 1 "$SLOTS"); do
    if aw_have_flock; then
      exec 9>"$DIR/slot$s"
      if flock -n 9; then
        echo "heavy slot $s acquired: $*" >&2
        "$@" 9>&-; rc=$?
        exec 9>&-
        exit $rc
      fi
      exec 9>&-
    else
      d="$DIR/slot$s.d"
      p=$(cat "$d/pid" 2>/dev/null)
      if [ -d "$d" ] && [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then rm -rf "$d"; fi
      if mkdir "$d" 2>/dev/null; then
        echo $$ >"$d/pid"
        trap 'rm -rf "$d"; exit 130' INT TERM
        echo "heavy slot $s acquired: $*" >&2
        "$@"; rc=$?
        rm -rf "$d"
        exit $rc
      fi
    fi
  done
  n=$((n + 1)); [ $((n % 6)) = 1 ] && echo "waiting for a heavy slot ($(date +%T))" >&2
  sleep "$POLL"
done
