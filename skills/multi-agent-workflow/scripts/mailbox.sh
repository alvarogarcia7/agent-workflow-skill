#!/usr/bin/env bash
# File-based FIFO mailboxes between the phase loops. A mailbox is a directory of message files; the oldest file name
# (sorted) is processed first, so order of arrival = order of processing. State lives on disk, not in any agent's context.
#
#   mailbox.sh send    <box> <task-id> [file|-]     enqueue (body from file or stdin); prints the message path
#   mailbox.sh claim   <box> <worker>               atomically take the OLDEST message into <box>/processing/<worker>/; prints its path (exit 1 if empty)
#   mailbox.sh done    <path>                       move a claimed message to <box>/done/
#   mailbox.sh reject  <path> <back-box> <reason>   move a claimed message to <back-box> as a rework message (reason prepended)
#   mailbox.sh list    <box>                        queued messages, oldest first
#   mailbox.sh count   <box>
#
# Boxes: phase1->2 = review, phase2->3 = push, phase3->4 = compare, phase4->1 = rework (new TODO/children go to the backlog).
# Config: STATE_DIR (default ~/.local/state/agent-workflow); box names are directories under $STATE_DIR/mailbox/.
ENV_FILE="${AGENT_WORKFLOW_ENV:-.agent-workflow.env}"; [ -f "$ENV_FILE" ] && . "$ENV_FILE"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/agent-workflow}"; ROOT="$STATE_DIR/mailbox"
cmd="${1:-}"; shift || true
box_dir() { mkdir -p "$ROOT/$1/processing" "$ROOT/$1/done"; echo "$ROOT/$1"; }
case "$cmd" in
  send)
    box=$(box_dir "$1"); id="$2"; src="${3:--}"
    ts=$(date +%s%N); f="$box/${ts}-${id}.md"; tmp="$box/.tmp-$$-${ts}"
    if [ "$src" = "-" ]; then cat > "$tmp"; else cp "$src" "$tmp"; fi
    mv "$tmp" "$f"; echo "$f";;                       # rename = atomic publish; readers never see half a message
  claim)
    box=$(box_dir "$1"); worker="$2"; mkdir -p "$box/processing/$worker"
    for f in $(ls "$box" 2>/dev/null | grep -E '^[0-9]+-.*\.md$' | sort); do
      if mv "$box/$f" "$box/processing/$worker/$f" 2>/dev/null; then echo "$box/processing/$worker/$f"; exit 0; fi   # mv wins for exactly one claimer
    done; exit 1;;
  done)
    p="$1"; box=$(dirname "$(dirname "$(dirname "$p")")"); mkdir -p "$box/done"; mv "$p" "$box/done/";;
  reject)
    p="$1"; back=$(box_dir "$2"); reason="$3"; id=$(basename "$p" .md | cut -d- -f2-)
    ts=$(date +%s%N); { printf -- '---\nrework: true\nreason: %s\n---\n' "$reason"; cat "$p"; } > "$back/.tmp-$$"; mv "$back/.tmp-$$" "$back/${ts}-${id}.md"
    box=$(dirname "$(dirname "$(dirname "$p")")"); mkdir -p "$box/done"; mv "$p" "$box/done/";;
  list)  box=$(box_dir "$1"); ls "$box" | grep -E '^[0-9]+-.*\.md$' | sort;;
  count) box=$(box_dir "$1"); ls "$box" | grep -cE '^[0-9]+-.*\.md$';;
  *) sed -n '2,15p' "$0"; exit 2;;
esac
