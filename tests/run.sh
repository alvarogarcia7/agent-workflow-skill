#!/usr/bin/env bash
# Test suite for the scripts. Needs bash, git, python3 (flock optional: the mkdir fallback is tested too).
# Usage: tests/run.sh      (exit 0 = all passed)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/skills/multi-agent-workflow/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; failn=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
bad()  { failn=$((failn + 1)); echo "FAIL - $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }
export PATH="$ROOT/tests/fake-glab:$PATH" HOME="$TMP/home"; mkdir -p "$HOME"
unset AGENT_WORKFLOW_ENV

# ---------- ci-trigger.sh ----------
HEADA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; HEADB=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
setup() { # name  -> sets F (fixtures) and STATE
  F="$TMP/$1/fix"; STATE="$TMP/$1/state dir"; rm -rf "$TMP/$1"; mkdir -p "$F" "$STATE"
  echo '{"id":1,"iid":7,"sha":"'$HEADA'"}' > "$F/mr.json"; echo '[]' > "$F/pipelines.json"
  echo '{"id":900,"status":"created"}' > "$F/post.out"
}
trig() { FAKE_GLAB_DIR="$F" STATE_DIR="$STATE" GITLAB_PROJECT=g%2Fr MR_IID=7 TRIGGER_INTERVAL=1 "$S/ci-trigger.sh" --once; }
posts() { cat "$F/post.count" 2>/dev/null || echo 0; }
js() { python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$STATE/ci-status.json" "$1"; }

setup t1; trig; trig
check "new head triggers exactly once" '[ "$(posts)" = 1 ]'
check "status written, no errors" '[ "$(js "d[\"error\"] is None and d[\"trigger_error\"] is None")" = True ]'

setup t2; echo '[{"id":50,"status":"success","sha":"mergeref111"}]' > "$F/pipelines.json"
trig; trig; trig
check "merged-results pipeline (sha != head) triggers once only" '[ "$(posts)" = 1 ]'
check "mr_head recorded for the triggered pipeline" '[ -f "$STATE/.triggered-$HEADA" ] && [ "$(cat "$STATE/.triggered-$HEADA")" = 900 ]'

setup t3; echo '[{"id":51,"status":"canceling","sha":"zzz"}]' > "$F/pipelines.json"; trig
check "canceling pipeline counts as active (no trigger)" '[ "$(posts)" = 0 ] && [ "$(js "d[\"active_pipelines\"]")" = 1 ]'
echo '[{"id":52,"status":"waiting_for_callback","sha":"zzz"}]' > "$F/pipelines.json"; trig
check "waiting_for_callback counts as active" '[ "$(posts)" = 0 ]'

setup t4; echo 'rate limited: 429 Too Many Requests' > "$F/pipelines.err"
FAKE_GLAB_DIR="$F" STATE_DIR="$STATE" GITLAB_PROJECT=g%2Fr MR_IID=7 TRIGGER_INTERVAL=1 bash -c "start=\$(date +%s); '$S/ci-trigger.sh' --once; echo \$((\$(date +%s)-start)) > '$TMP/elapsed'"
check "429: no trigger, error in status, loop would back off" '[ "$(posts)" = 0 ] && grep -q 429 "$STATE/ci-status.json" && grep -q "backing off 2s" "$STATE/ci-trigger.log"'

setup t5; echo '{"message":"404 Project Not Found"}' > "$F/mr.json"; trig
check "404 JSON body is an error, not a pipeline list" '[ "$(posts)" = 0 ] && grep -q "404" "$STATE/ci-status.json"'

setup t6; echo '{"message":"403 Forbidden"}' > "$F/post.out"; echo 1 > "$F/post.rc"; trig; trig
check "403 on POST: not marked, trigger_error set, retried" '[ "$(posts)" = 2 ] && [ ! -f "$STATE/.triggered-$HEADA" ] && grep -q 403 "$STATE/ci-status.json" && grep -q "TRIGGER FAILED" "$STATE/ci-failures.log"'
echo '{"message":"400 No stages"}' > "$F/post.out"; echo 0 > "$F/post.rc"; trig
check "error body with exit 0 is also a failed trigger" '[ ! -f "$STATE/.triggered-$HEADA" ]'

setup t7; STATE="$TMP/t7/it's a \"state\" dir"; mkdir -p "$STATE"; trig
check "STATE_DIR containing quotes works (valid atomic JSON)" '[ "$(posts)" = 1 ] && [ -z "$(ls "$STATE" | grep tmp)" ] && [ "$(js "d[\"mr_head\"]")" = "$HEADA" ]'

setup t8; echo '[{"id":60,"status":"failed","sha":"'$HEADA'"}]' > "$F/pipelines.json"
echo '[{"name":"unit","id":5,"status":"failed","failure_reason":"script_failure"},{"name":"lint","id":6,"status":"success"}]' > "$F/jobs-60.json"; trig; trig
check "failed pipeline on the head: reported once, not re-triggered" '[ "$(posts)" = 0 ] && [ "$(grep -c "pipeline 60 FAILED" "$STATE/ci-failures.log")" = 1 ] && grep -q "unit" "$STATE/ci-failures.log" && [ "$(js "d[\"last_pipeline\"][\"jobs\"][\"lint\"]")" = success ]'

setup t9; trig; echo '{"id":1,"iid":7,"sha":"'$HEADB'"}' > "$F/mr.json"; trig
check "a newer head triggers again and old markers are pruned" '[ "$(posts)" = 2 ] && [ ! -f "$STATE/.triggered-$HEADA" ] && [ -f "$STATE/.triggered-$HEADB" ]'

# ---------- heavy.sh ----------
conc() { # prints max concurrency from a log of "s"/"e" lines
  python3 -I -c 'import sys
c=m=0
for l in open(sys.argv[1]).read().split():
    c+=1 if l=="s" else -1; m=max(m,c)
print(m)' "$1"; }
for mode in flock mkdir; do
  [ "$mode" = mkdir ] && export AW_NO_FLOCK=1 || unset AW_NO_FLOCK
  [ "$mode" = flock ] && ! command -v flock >/dev/null && { echo "skip - flock not installed"; continue; }
  H="$TMP/heavy-$mode"; mkdir -p "$H"; : > "$H/log"
  job='echo s >> "$1"; sleep 2; echo e >> "$1"'
  for i in 1 2 3; do STATE_DIR="$H" HEAVY_SLOTS=2 HEAVY_POLL=1 "$S/heavy.sh" bash -c "$job" _ "$H/log" 2>/dev/null & done; wait
  check "heavy.sh ($mode): 3 jobs, 2 slots -> max concurrency 2, all ran" '[ "$(conc "$H/log")" = 2 ] && [ "$(grep -c e "$H/log")" = 3 ]'
  # a job that leaves a background process must not hold the slot
  STATE_DIR="$H" HEAVY_SLOTS=1 HEAVY_POLL=1 "$S/heavy.sh" bash -c 'sleep 20 & echo $! > "$1"' _ "$H/bgpid" 2>/dev/null
  t0=$(date +%s); STATE_DIR="$H" HEAVY_SLOTS=1 HEAVY_POLL=1 "$S/heavy.sh" true 2>/dev/null; t1=$(date +%s)
  kill "$(cat "$H/bgpid")" 2>/dev/null
  if [ "$mode" = flock ]; then check "heavy.sh (flock): background child does not hold the slot" '[ $((t1 - t0)) -lt 5 ]'; fi
done
unset AW_NO_FLOCK
"$S/heavy.sh" >/dev/null 2>&1; check "heavy.sh without command exits 2" '[ $? = 2 ]'
HEAVY_SLOTS=abc "$S/heavy.sh" true >/dev/null 2>&1; check "heavy.sh rejects non-numeric HEAVY_SLOTS" '[ $? = 2 ]'

# ---------- keep-both.py ----------
K="$TMP/kb"; mkdir -p "$K"
printf 'head\n<<<<<<< HEAD\n**D-01** ours\n=======\n**D-02** theirs\n>>>>>>> branch\ntail\n' > "$K/merge.md"
printf 'head\n<<<<<<< HEAD\n**D-01** ours\n||||||| base\n**D-00** base\n=======\n**D-02** theirs\n>>>>>>> branch\ntail\n' > "$K/diff3.md"
printf '<<<<<<< HEAD\n**D-05** a\n=======\n**D-05** b\n>>>>>>> x\n' > "$K/dup.md"
printf '<<<<<<< HEAD\nunterminated\n' > "$K/broken.md"
python3 -I "$S/keep-both.py" "$K/merge.md" "$K/diff3.md" >/dev/null; rc=$?
check "keep-both: merge + diff3 styles resolved, exit 0" '[ $rc = 0 ] && ! grep -q "<<<<<<<\|=======\|>>>>>>>\|||||||" "$K/merge.md" "$K/diff3.md"'
check "keep-both: base section dropped, blank line between sides" '! grep -q "D-00" "$K/diff3.md" && [ "$(sed -n 2,4p "$K/diff3.md")" = "$(printf "**D-01** ours\n\n**D-02** theirs")" ]'
out=$(python3 -I "$S/keep-both.py" "$K/dup.md" 2>&1); check "keep-both: duplicate D-nn id reported" 'echo "$out" | grep -q "duplicate decision id D-05"'
python3 -I "$S/keep-both.py" "$K/broken.md" >/dev/null; check "keep-both: leftover markers -> non-zero exit" '[ $? = 1 ]'

# ---------- safe-push.sh ----------
G="$TMP/git"; mkdir -p "$G"; export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
git init -q --bare "$G/remote.git"; git clone -q "$G/remote.git" "$G/w1" 2>/dev/null; git clone -q "$G/remote.git" "$G/w2" 2>/dev/null
( cd "$G/w1" && git checkout -q -b main && echo 1 > a && git add a && git commit -qm one && git push -q origin main )
( cd "$G/w2" && git fetch -q && git checkout -q -b main origin/main )
export STATE_DIR="$TMP/pushstate"
( cd "$G/w1" && echo 2 > b && git add b && git commit -qm two && env -u BRANCH PUSH_OPTS= "$S/safe-push.sh" ) >/dev/null 2>&1
check "safe-push: refuses to run without BRANCH" '[ $? != 0 ] && [ "$(git -C "$G/remote.git" rev-list --count main)" = 1 ]'
( cd "$G/w1" && BRANCH=main PUSH_OPTS= "$S/safe-push.sh" ) >/dev/null 2>&1
check "safe-push: pushes with PUSH_OPTS empty" '[ "$(git -C "$G/remote.git" rev-list --count main)" = 2 ]'
( cd "$G/w2" && echo 3 > c && git add c && git commit -qm three && BRANCH=main PUSH_OPTS= "$S/safe-push.sh" ) >/dev/null 2>&1
check "safe-push: rebases when behind, then pushes" '[ "$(git -C "$G/remote.git" rev-list --count main)" = 3 ]'
( cd "$G/w1" && echo 4 > d && git add d && git commit -qm four && echo dirty >> a && BRANCH=main PUSH_OPTS= "$S/safe-push.sh" ) >/dev/null 2>&1
check "safe-push: dirty tracked tree is refused" '[ $? != 0 ] && [ "$(git -C "$G/remote.git" rev-list --count main)" = 3 ]'
( cd "$G/w1" && git checkout -q a && BRANCH=main PUSH_OPTS= POST_REBASE_CHECK=false "$S/safe-push.sh" ) >/dev/null 2>&1
check "safe-push: POST_REBASE_CHECK failure blocks the push" '[ "$(git -C "$G/remote.git" rev-list --count main)" = 3 ]'
( cd "$G/w1" && BRANCH=main PUSH_OPTS= POST_REBASE_CHECK=true "$S/safe-push.sh" ) >/dev/null 2>&1
check "safe-push: POST_REBASE_CHECK success allows the push" '[ "$(git -C "$G/remote.git" rev-list --count main)" = 4 ]'
out=$( cd "$G/w1" && echo 5 > e && git add e && git commit -qm five && AGENT_WORKFLOW_ENV="$TMP/missing.env" BRANCH=main "$S/safe-push.sh" 2>&1 )
check "safe-push: default -o ci.skip is passed (local remote rejects push options)" 'echo "$out" | grep -qi "push option" && [ "$(git -C "$G/remote.git" rev-list --count main)" = 4 ]'
printf 'BRANCH=main\nPUSH_OPTS=\n' > "$G/w1/../.agent-workflow.env"
( cd "$G/w1" && AGENT_WORKFLOW_ENV="$G/.agent-workflow.env" "$S/safe-push.sh" ) >/dev/null 2>&1
check "safe-push: env file via AGENT_WORKFLOW_ENV" '[ "$(git -C "$G/remote.git" rev-list --count main)" = 5 ]'

echo; echo "passed: $pass  failed: $failn"; [ "$failn" = 0 ]
