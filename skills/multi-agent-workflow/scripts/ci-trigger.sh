#!/usr/bin/env bash
# CI trigger loop for GitLab merge-request pipelines (run by ONE "CI agent" instance). Agents push with ci.skip (see
# safe-push.sh), so nothing runs unless this loop creates a pipeline. Every TRIGGER_INTERVAL seconds it
#  1) reads the MR pipelines (one call) and finds the active ones and the newest NON-skipped one;
#  2) if nothing is active and the MR head is not covered by a non-skipped pipeline: creates ONE pipeline for it;
#  3) writes $STATE_DIR/ci-status.json (agents READ this file instead of polling GitLab, which rate-limits with 429) and
#     appends failed pipelines with their failed jobs to $STATE_DIR/ci-failures.log.
# Config (env.example): GITLAB_PROJECT (url-encoded path, e.g. group%2Frepo), MR_IID, STATE_DIR, TRIGGER_INTERVAL.
# Needs: glab (authenticated), python3. For GitHub Actions adapt the three `api` calls with `gh api`.
# Usage: ci-trigger.sh [--once]
ENV_FILE="${AGENT_WORKFLOW_ENV:-.agent-workflow.env}"; [ -f "$ENV_FILE" ] && . "$ENV_FILE"
: "${GITLAB_PROJECT:?set GITLAB_PROJECT (url-encoded project path) in the env file}"; : "${MR_IID:?set MR_IID}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/agent-workflow}"; INTERVAL="${TRIGGER_INTERVAL:-180}"
mkdir -p "$STATE_DIR"; P="projects/$GITLAB_PROJECT"
LOG="$STATE_DIR/ci-trigger.log"; FAIL="$STATE_DIR/ci-failures.log"; STATUS="$STATE_DIR/ci-status.json"
api() { out=$(glab api "$1" 2>&1); case "$out" in "["*|"{"*) echo "$out";; *) echo "$(date +%T) api error: ${out:0:80}" >> "$LOG"; return 1;; esac; }
while true; do
  wait=$INTERVAL
  if pipes=$(api "$P/merge_requests/$MR_IID/pipelines?per_page=40") && mr=$(api "$P/merge_requests/$MR_IID"); then
    export PIPES="$pipes" MR="$mr"
    read -r head active lid lst lsha <<<"$(python3 -I -c "
import os,json
p=json.loads(os.environ['PIPES']); m=json.loads(os.environ['MR'])
act=[x for x in p if x['status'] in ('running','pending','created','preparing','waiting_for_resource','scheduled')]
real=[x for x in p if x['status']!='skipped']
l=real[0] if real else {'id':0,'status':'none','sha':'none'}
print(m['sha'], len(act), l['id'], l['status'], l['sha'])")"
    echo "$(date +%T) active=$active head=${head:0:7} last-real=$lid:$lst:${lsha:0:7}" >> "$LOG"
    jobs="[]"; if [ "$lid" != "0" ] && jobsraw=$(api "$P/pipelines/$lid/jobs?per_page=50"); then jobs="$jobsraw"; fi
    export JOBS="$jobs" HEAD="$head" ACTIVE="$active" LID="$lid" LST="$lst" LSHA="$lsha"
    python3 -I -c "
import os,json,datetime
jobs=json.loads(os.environ['JOBS'])
json.dump({'updated':datetime.datetime.now().strftime('%H:%M:%S'),'mr_head':os.environ['HEAD'],
 'active_pipelines':int(os.environ['ACTIVE']),
 'last_pipeline':{'id':int(os.environ['LID']),'status':os.environ['LST'],'sha':os.environ['LSHA'],
 'jobs':{j['name']:j['status'] for j in jobs}}},open('$STATUS','w'),indent=1)"
    if [ "$lst" = "failed" ] && [ ! -f "$STATE_DIR/.reported-$lid" ] && [ "$active" = "0" ]; then
      touch "$STATE_DIR/.reported-$lid"
      { echo "=== $(date +%T) pipeline $lid FAILED on ${lsha:0:7}"; python3 -I -c "
import os,json
[print(' ',j['name'],j['id'],j.get('failure_reason') or '') for j in json.loads(os.environ['JOBS']) if j['status']=='failed']"; } >> "$FAIL"
    fi
    if [ "$active" = "0" ] && [ -n "$head" ] && [ "$lsha" != "$head" ]; then
      r=$(glab api -X POST "$P/merge_requests/$MR_IID/pipelines" 2>&1 | head -c 200)
      echo "$(date +%T) triggered pipeline for ${head:0:7}: ${r:0:100}" >> "$LOG"
    fi
  else
    wait=$((INTERVAL * 2))   # rate limited or API down: back off
  fi
  [ "$1" = "--once" ] && break
  sleep "$wait"
done
