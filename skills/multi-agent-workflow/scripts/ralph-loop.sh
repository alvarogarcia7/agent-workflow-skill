#!/usr/bin/env bash
# Ralph Wiggum loop: run the same prompt in a FRESH agent context every iteration; all progress lives on disk (git, backlog,
# mailboxes), never in the context. One iteration = take the oldest message of the phase's inbox, process it completely,
# hand the result to the next phase's outbox. Stop when the inbox is empty and STOP_WHEN_EMPTY=1 (or on a STOP file).
# Usage: ralph-loop.sh <phase-name> <inbox> <prompt-file>          Config: AGENT_CMD (default: claude -p), POLL (seconds)
#   AGENT_CMD examples:  "claude -p --model haiku"   "claude -p --model opus"
ENV_FILE="${AGENT_WORKFLOW_ENV:-.agent-workflow.env}"; [ -f "$ENV_FILE" ] && . "$ENV_FILE"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/agent-workflow}"; HERE="$(cd "$(dirname "$0")" && pwd)"
phase="$1"; inbox="$2"; prompt="$3"; worker="${WORKER:-$phase-$$}"; AGENT_CMD="${AGENT_CMD:-claude -p}"; POLL="${POLL:-30}"
mkdir -p "$STATE_DIR/loops"; log="$STATE_DIR/loops/$phase.log"
while [ ! -f "$STATE_DIR/STOP" ] && [ ! -f "$STATE_DIR/STOP-$phase" ]; do
  if msg=$("$HERE/mailbox.sh" claim "$inbox" "$worker"); then
    echo "$(date +%T) $phase: processing $msg" >> "$log"
    # the agent gets the phase prompt + the message path; it must call mailbox.sh done/reject itself when finished
    { cat "$prompt"; printf '\n\n## Message to process\nPath: %s\n\n' "$msg"; cat "$msg"; } | $AGENT_CMD >> "$log" 2>&1
    # an iteration that left the message in processing/ is returned to the inbox head so it is retried, not lost
    if [ -f "$msg" ]; then echo "$(date +%T) $phase: not finished, re-queued" >> "$log"; mv "$msg" "$STATE_DIR/mailbox/$inbox/$(basename "$msg")"; sleep "$POLL"; fi
  else
    [ "${STOP_WHEN_EMPTY:-0}" = 1 ] && break
    sleep "$POLL"
  fi
done
