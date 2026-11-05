# Forge reference for mr-pipeline-merge

All commands take `HOST` and `PROJECT` (e.g. `group/sub/repo`, `owner/repo`) from the
remote URL. `OWNER`/`REPO` are the last two path segments. Nothing here merges.

## Parse the remote and detect the forge

```sh
url=$(git remote get-url "$REMOTE")
case $url in
  *://*)  rest=${url#*://}; rest=${rest#*@}; proj=${rest#*/}; host=${rest%%/*}; host=${host%:*} ;;
  *@*:*)  rest=${url#*@};   proj=${rest#*:};  host=${rest%%:*} ;;
esac
proj=${proj%.git}; proj=${proj%/}          # PROJECT (not "path": zsh ties it to PATH)
code() { curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$1"; }
if [ -n "$FORGE" ]; then forge=$FORGE
elif [ "$host" = github.com ]; then forge=github
elif [ "$(code https://$host/api/v1/version)" = 200 ]; then forge=gitea      # Gitea, Forgejo
elif [ "$(code https://$host/api/v4/version)" = 200 ] || [ "$(code https://$host/api/v4/version)" = 401 ]; then forge=gitlab
elif curl -sSI --max-time 10 "https://$host/api/v3/" | grep -qi x-github-enterprise-version; then forge=github
else echo "cannot detect forge at $host" >&2; exit 2; fi
```

CLI readiness, per forge: `glab auth status` (lists hosts), `gh auth status -h $HOST`,
`tea login list` (an entry whose URL matches `https://$HOST`). Missing or not logged
in: stop.

Pending statuses (keep polling) and terminal ones (stop):

| forge  | pending                                                     | success                              | failure (list jobs)                                         |
|--------|-------------------------------------------------------------|--------------------------------------|-------------------------------------------------------------|
| gitlab | `created waiting_for_resource preparing pending running canceling` | `success`                   | `failed canceled skipped manual scheduled`                  |
| github | run `status` in `queued in_progress waiting requested pending` | every run `completed` with conclusion `success`, `neutral` or `skipped` | any other conclusion (`failure cancelled timed_out action_required startup_failure`) |
| gitea  | combined status `pending`                                   | combined status `success`            | `failure error`                                             |

## GitLab (`glab`)

`ENC=$(printf %s "$PROJECT" | sed 's,/,%2F,g')`; API calls are
`glab api --hostname $HOST ...`; MR commands take `-R $HOST/$PROJECT`.

| step | command |
|------|---------|
| find PR | `glab mr list -R $HOST/$PROJECT --source-branch $BRANCH --target-branch $TARGET -F json` (`iid`, `web_url`, `state`, `sha`) |
| create | `glab mr create -R $HOST/$PROJECT -s $BRANCH -b $TARGET -t "<title>" -d "<description>" --yes` |
| PR state | `glab mr view $IID -R $HOST/$PROJECT -F json` (`state` opened/merged/closed, `sha`) |
| pipelines for SHA | `glab api --hostname $HOST "projects/$ENC/pipelines?sha=$REVIEWED_SHA"` (`id`, `status`, `ref`; the filter needs the full 40-char SHA) |
| pipeline detail | `glab api --hostname $HOST projects/$ENC/pipelines/$ID` (`status`, `duration` in seconds) |
| last 3 successful | `glab api --hostname $HOST "projects/$ENC/pipelines?status=success&per_page=3"`, then detail for each (the list omits `duration`) |
| jobs | `glab api --hostname $HOST projects/$ENC/pipelines/$ID/jobs` (`name`, `status`, `allow_failure`, `web_url`) |
| close | `glab mr close $IID -R $HOST/$PROJECT`; comment: `glab mr note create $IID -R $HOST/$PROJECT -m "<text>"` |
| PR reference in commit messages | `!$IID` |

## GitHub (`gh`), github.com or Enterprise

Repo flag `-R $HOST/$OWNER/$REPO`; API calls `gh api --hostname $HOST ...`.

| step | command |
|------|---------|
| find PR | `gh pr list -R $HOST/$OWNER/$REPO --head $BRANCH --base $TARGET --state open --json number,url,headRefOid` |
| create | `gh pr create -R $HOST/$OWNER/$REPO --head $BRANCH --base $TARGET --title "<title>" --body "<description>"` |
| PR state | `gh pr view $N -R $HOST/$OWNER/$REPO --json state,headRefOid,url` (`OPEN`, `MERGED`, `CLOSED`) |
| runs for SHA | `gh run list -R $HOST/$OWNER/$REPO --commit $REVIEWED_SHA --json databaseId,name,status,conclusion,url` (wait for all) |
| run duration | `gh api --hostname $HOST repos/$OWNER/$REPO/actions/runs/$ID/timing` → `run_duration_ms` / 1000 |
| last 3 successful | `gh run list -R $HOST/$OWNER/$REPO --status success --limit 3 --json databaseId`, then timing for each |
| jobs | `gh run view $ID -R $HOST/$OWNER/$REPO --json jobs` (`name`, `conclusion`, `url`), or `gh pr checks $N -R ... --json name,state,link` |
| close | `gh pr close $N -R $HOST/$OWNER/$REPO --comment "<text>"` |
| PR reference in commit messages | `#$N` |

Cache `pipeline` as the run id of the longest run when several ran for one commit; the
wait is governed by the slowest.

## Gitea / Forgejo (`tea` + REST API)

`tea` has no raw API command. REST calls:
`curl -fsS -H "Authorization: token $TOKEN" https://$HOST/api/v1/...` with `TOKEN`
from `GITEA_TOKEN`, `FORGEJO_TOKEN`, or the matching login's `token` in
`~/.config/tea/config.yml`. `tea` commands take `--login <name> --repo $OWNER/$REPO`.

| step | command |
|------|---------|
| find PR | `GET repos/$OWNER/$REPO/pulls?state=open` and pick `head.ref == $BRANCH && base.ref == $TARGET` (`number`, `html_url`, `head.sha`) |
| create | `tea pr create --login $LOGIN --repo $OWNER/$REPO --head $BRANCH --base $TARGET --title "<title>" --description "<description>"` |
| PR state | `GET repos/$OWNER/$REPO/pulls/$N` (`state` open/closed, `merged`, `head.sha`) |
| pipeline for SHA | `GET repos/$OWNER/$REPO/commits/$REVIEWED_SHA/status` → combined `state`, `statuses[]` (`context`, `status`, `target_url`). Covers Gitea/Forgejo Actions and any CI that reports commit statuses. |
| duration | `GET repos/$OWNER/$REPO/actions/tasks` filtered on `head_sha`: max `updated_at` minus min `run_started_at`. Endpoint absent (older Gitea, or non-Actions CI): measure the wall-clock from the first `pending` seen to the terminal status and cache that. |
| last 3 successful | same `actions/tasks` listing grouped by `run_number` with all tasks `success`; absent: skip bootstrap, start at 120 |
| jobs | the `statuses[]` entries whose `status` is `failure` or `error`, with `target_url` |
| close | `tea pr close $N --login $LOGIN --repo $OWNER/$REPO`; comment: `tea comment $N "<text>" --login $LOGIN --repo $OWNER/$REPO` |
| PR reference in commit messages | `#$N` |
