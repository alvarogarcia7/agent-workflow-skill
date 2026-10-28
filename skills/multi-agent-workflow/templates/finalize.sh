#!/usr/bin/env bash
# Batch finalizer for Backlog.md tasks. Copy per batch, fill the TASKS array, run from the checkout you commit from.
#   ./finalize.sh --dry-run    print every command, change nothing
#   ./finalize.sh              run them
# Idempotent: re-running is safe (checks already set stay set; Done stays Done). Children before parents.
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
PIPELINE="<pipeline id>"
run() { # print the command %q-quoted; run it unless dry-run; report failures and continue
  printf '+'; printf ' %q' "$@"; printf '\n'
  [ "$DRY" = 1 ] && return 0
  "$@" || echo "!! failed: $*" >&2
}
status_of() { backlog task view "$1" --plain 2>/dev/null | sed -n 's/^Status:[^A-Za-z]*//p' | head -1; }
children_done() { # fails (prints the open child) unless every child of $1 reads Done
  local c ok=0
  for c in $(backlog task list --plain 2>/dev/null | grep -o "$1\.[0-9.]*" | sort -u); do
    [ "$(status_of "$c")" = "Done" ] || { echo "!! child $c of $1 is not Done" >&2; ok=1; }
  done
  return $ok
}
finalize() { # id "ac indexes" "dod indexes" "evidence" "summary"
  local id="$1" ac="$2" dod="$3" ev="$4" sum="$5" args=() i
  for i in $ac; do args+=(--check-ac "$i"); done
  for i in $dod; do args+=(--check-dod "$i"); done
  if ! children_done "$id"; then echo "skip $id (children not Done)" >&2; return; fi
  run backlog task edit "$id" "${args[@]}" --append-notes "Evidence (pipeline $PIPELINE): $ev" --final-summary "$sum" -s Done
}
# finalize <id> "1 2 3" "1 2" "<test names>" "<summary>"
# children first, parents last:
# finalize TASK-1.1 "1 2" "1" "spec foo, spec bar" "Added X."
# finalize TASK-1   "1"   "1" "children done"      "Epic complete."
