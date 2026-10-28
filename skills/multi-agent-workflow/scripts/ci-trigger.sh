#!/usr/bin/env bash
# CI trigger loop for GitLab merge-request pipelines (run by ONE "CI agent" instance). Agents push with ci.skip (see
# safe-push.sh), so nothing runs unless this loop creates a pipeline. Every TRIGGER_INTERVAL seconds it
#  1) reads the MR pipelines and finds the active ones and the newest NON-skipped one;
#  2) if nothing is active, the MR head is not covered by that pipeline AND this head was not triggered before
#     (marker $STATE_DIR/.triggered-<head>): creates ONE pipeline for it. The marker makes it safe with merged-results /
#     merge-train pipelines, whose `sha` is a merge commit and never equals the MR head (without it: a pipeline per cycle);
#  3) writes $STATE_DIR/ci-status.json atomically (agents READ it instead of polling GitLab, which rate-limits with 429)
#     and appends failed pipelines with their failed jobs to $STATE_DIR/ci-failures.log.
# A failed trigger (403, 400, 429...) is NOT marked: it is logged, put in ci-status.json as "trigger_error" and retried
# with exponential backoff. A pipeline that FAILED is not re-triggered for the same head (a repeating failure is a bug);
# to force a re-run, delete $STATE_DIR/.triggered-<head>. Markers of older heads are pruned.
# Status file: see references/ci-gitlab.md. Staleness rule: if "updated" is older than 3 * TRIGGER_INTERVAL the loop is dead.
# Config (env.example): GITLAB_PROJECT (url-encoded path, e.g. group%2Frepo), MR_IID, STATE_DIR, TRIGGER_INTERVAL.
# Needs: glab (authenticated), python3. GitHub Actions: see references/ci-github.md.
# Permissions: creating MR pipelines needs a token with `api` scope and the Developer role (plus push/merge rights when
# the source branch is protected), and .gitlab-ci.yml must define jobs for merge_request_event; otherwise the POST
# returns 400 "No stages / jobs for this pipeline" or 403.
# Usage: ci-trigger.sh [--once]
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
aw_load_env; aw_defaults
: "${GITLAB_PROJECT:?set GITLAB_PROJECT (url-encoded project path) in the env file}"; : "${MR_IID:?set MR_IID}"
INTERVAL="${TRIGGER_INTERVAL:-180}"; aw_require_uint TRIGGER_INTERVAL "$INTERVAL"
P="projects/$GITLAB_PROJECT"
LOG="$STATE_DIR/ci-trigger.log"; FAIL="$STATE_DIR/ci-failures.log"; STATUS="$STATE_DIR/ci-status.json"
export STATE_DIR STATUS INTERVAL
log() { echo "$(aw_utc) $*" >> "$LOG"; }
apifail() { log "api error: ${1:0:120}"; echo "${1:0:200}" > "$STATE_DIR/.api-error"; return 1; }
api() {
  local out
  out=$(glab api "$1" 2>&1) || { apifail "$out"; return 1; }
  case "$out" in '{"message"'*|'{"error"'*) apifail "$out"; return 1;; "["*|"{"*) echo "$out";; *) apifail "$out"; return 1;; esac
}
# write_status: atomic write of the status file from the exported variables (nothing is interpolated into the source).
write_status() {
  python3 -I -c '
import os, json, datetime
st = os.environ["STATUS"]
jobs = json.loads(os.environ.get("JOBS") or "[]")
old = {}
try:
    old = json.load(open(st))
except Exception:
    pass
mapping = {}
sd = os.environ["STATE_DIR"]
for n in os.listdir(sd):
    if n.startswith(".triggered-"):
        try:
            mapping[open(os.path.join(sd, n)).read().strip()] = n[len(".triggered-"):]
        except Exception:
            pass
lid = os.environ.get("LID", "0")
head = os.environ.get("HEAD", "")
lsha = os.environ.get("LSHA", "")
doc = {"updated": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
       "interval": int(os.environ["INTERVAL"]),
       "error": os.environ.get("API_ERROR") or None,
       "trigger_error": os.environ.get("TRIGGER_ERROR") or None}
if os.environ.get("HAVE_DATA") == "1":
    doc.update({"mr_head": head, "active_pipelines": int(os.environ["ACTIVE"]),
                "last_pipeline": {"id": int(lid), "status": os.environ["LST"], "sha": lsha,
                                  "mr_head": mapping.get(lid) or (head if lsha == head else None),
                                  "jobs": {j["name"]: j["status"] for j in jobs}}})
else:
    for k in ("mr_head", "active_pipelines", "last_pipeline"):
        if k in old:
            doc[k] = old[k]
tmp = st + ".tmp"
with open(tmp, "w") as f:
    json.dump(doc, f, indent=1)
os.replace(tmp, st)'
}
fails=0
while true; do
  API_ERROR=""; TRIGGER_ERROR=""; HAVE_DATA=0; ok=1
  if pipes=$(api "$P/merge_requests/$MR_IID/pipelines?per_page=40") && mr=$(api "$P/merge_requests/$MR_IID"); then
    export PIPES="$pipes" MR="$mr"
    read -r head active lid lst lsha <<<"$(python3 -I -c '
import os, json
p = json.loads(os.environ["PIPES"]); m = json.loads(os.environ["MR"])
act = [x for x in p if x["status"] in ("created", "waiting_for_resource", "preparing", "waiting_for_callback", "pending", "running", "canceling", "scheduled")]
real = [x for x in p if x["status"] != "skipped"]
l = real[0] if real else {"id": 0, "status": "none", "sha": "none"}
print(m["sha"], len(act), l["id"], l["status"], l["sha"])')"
    log "active=$active head=${head:0:7} last-real=$lid:$lst:${lsha:0:7}"
    jobs="[]"; if [ "$lid" != "0" ] && jobsraw=$(api "$P/pipelines/$lid/jobs?per_page=100"); then jobs="$jobsraw"; fi
    if [ "$lst" = "failed" ] && [ ! -f "$STATE_DIR/.reported-$lid" ] && [ "$active" = "0" ]; then
      touch "$STATE_DIR/.reported-$lid"
      { echo "=== $(aw_utc) pipeline $lid FAILED on ${lsha:0:7}"; JOBS="$jobs" python3 -I -c '
import os, json
[print(" ", j["name"], j["id"], j.get("failure_reason") or "") for j in json.loads(os.environ["JOBS"]) if j["status"] == "failed"]'; } >> "$FAIL"
    fi
    mark="$STATE_DIR/.triggered-$head"
    if [ "$active" = "0" ] && [ -n "$head" ] && [ "$lsha" != "$head" ] && [ ! -f "$mark" ]; then
      r=$(glab api -X POST "$P/merge_requests/$MR_IID/pipelines" 2>&1); rrc=$?
      newid=$(R="$r" python3 -I -c '
import os, json
try:
    d = json.loads(os.environ["R"])
    print(d["id"] if isinstance(d, dict) and isinstance(d.get("id"), int) and "message" not in d else "")
except Exception:
    print("")')
      if [ "$rrc" = 0 ] && [ -n "$newid" ]; then
        echo "$newid" > "$mark"
        for old in "$STATE_DIR"/.triggered-*; do [ "$old" = "$mark" ] || rm -f "$old"; done
        log "triggered ${head:0:7}: pipeline $newid"
        active=1
      else
        TRIGGER_ERROR="${r:0:200}"; ok=0
        log "TRIGGER FAILED ${head:0:7}: ${r:0:200}"
        echo "$(aw_utc) TRIGGER FAILED ${head:0:7}: ${r:0:200}" >> "$FAIL"
      fi
    fi
    HAVE_DATA=1
    JOBS="$jobs" HEAD="$head" ACTIVE="$active" LID="$lid" LST="$lst" LSHA="$lsha" HAVE_DATA=1 API_ERROR="" TRIGGER_ERROR="$TRIGGER_ERROR" write_status
  else
    ok=0; API_ERROR=$(cat "$STATE_DIR/.api-error" 2>/dev/null); API_ERROR="${API_ERROR:-api error}"
    API_ERROR="$API_ERROR" TRIGGER_ERROR="" HAVE_DATA=0 write_status
  fi
  if [ "$ok" = 1 ]; then fails=0; wait=$INTERVAL
  else fails=$((fails + 1)); wait=$((INTERVAL * (1 << (fails < 4 ? fails : 4)))); log "backing off ${wait}s (failure $fails)"; fi
  [ "${1:-}" = "--once" ] && break
  sleep "$wait"
done
