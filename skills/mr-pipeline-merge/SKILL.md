---
name: mr-pipeline-merge
description: Ship a local feature branch through a pull/merge request to main on whatever forge the git remote points at (GitLab, GitHub, Gitea/Forgejo, self-hosted included). Push, open the request, wait for its pipeline on a cached schedule, report readiness, then after an explicit user approval merge locally (ff-only, merge commit or squash) with the repo's commit-policy identity, push main, and delete the remote branch with --force-with-lease. Never merges in the forge UI or API.
---

# MR pipeline merge

Run the steps in order. Gates (4 and 5) need the user. Never add `skip ci`
markers. Never add `Co-Authored-By` trailers: the repo's pre-push hook rejects them.
"PR" below means the forge's request object (GitLab calls it an MR).

## Inputs
- `BRANCH`: local branch to ship. `TARGET`: normally `main`. `REMOTE`: normally `origin`.
- Forge and project: derived from `git remote get-url $REMOTE`, never hard-coded.
  `FORGE=gitlab|github|gitea` in the environment overrides detection.
- Identity: `git config user.name` / `user.email` in the `$TARGET` worktree. If
  `.commit-policy` exists at the repo root, the email must be listed there, else stop.

## 0. Detect the forge
Parse host and project path from the remote URL, then detect the forge
(`github.com` is GitHub; otherwise probe the API) as shown in
`references/forges.md`. Stop if the forge's CLI (`glab`, `gh`, `tea`) is not installed
or not logged in to that host. Every later forge call takes the detected host and
project explicitly; do not rely on CLI defaults.

## 1. Rebase and push
1. `git fetch $REMOTE`. If `BRANCH` is not already on top of `$REMOTE/$TARGET`, rebase it
   there. Stop on conflicts. If a PR already exists, say that the rebase rewrites the
   commits under review.
2. Push. Branch new on the remote: `git push -u $REMOTE HEAD:refs/heads/$BRANCH`.
   Branch already there: the same push with
   `--force-with-lease=$BRANCH:$(git rev-parse $REMOTE/$BRANCH)`. Never `--force`.
3. Record the pushed SHA as `REVIEWED_SHA`. Everything downstream checks against it.

## 2. Open or update the PR
- Look the PR up first (open, head `$BRANCH`, base `$TARGET`). If it exists, record its
  number and URL; the push already updated it. Do not create another.
- Otherwise create it with the forge CLI, non-interactively, with a title and a
  description that ends with the Claude Code attribution line. Record number and URL.

## 3. Wait for the pipeline
**Find it:** poll the forge for pipeline runs whose `sha` is `REVIEWED_SHA` (not by
branch name: GitLab merge-request pipelines run on `refs/merge-requests/N/head`). It
can take a few seconds to appear. GitHub may start several workflow runs for one
commit; wait for all of them. None after 60 seconds: report that the forge ran no
pipeline for this commit and go to step 4 with status `none`.

**Average, from the cache** `<repo root>/.mr-pipeline-timing.json` (git-ignored):
```json
{"forge": "gitlab", "project": "gitlab.example.com/group/repo", "unit": "seconds",
 "successful_pipelines": [{"pipeline": 34692, "sha": "2d586586", "duration": 122}],
 "average": 122.0}
```
- File present and `forge`/`project` match: use its `average`. Do not query for it.
- Otherwise: take the last 3 successful pipelines, fetching each one's duration as the
  forge exposes it (see the reference). Write the file; `average` is their mean. If the
  forge exposes no durations, start with 120 and let the measurements fill the file.

**Schedule:** one check after `average` seconds, then 5 checks one minute apart, then 5
checks two minutes apart. Deadline: `average` + 15 minutes after the push. Stop early
when the status is no longer pending/running (per-forge status lists in the reference).
Run the loop in the background; do not block on sleep. Never run a second loop at once.

**Cache update:** only on `success`, append `{pipeline, sha, duration}` and recompute
`average` as the mean of all entries. Never add failed, canceled or timed-out runs.

## 4. Report
- `success`: say the pipeline passed and the PR is ready for review, with its URL.
- `failed` (or canceled, skipped, manual, blocked): list the failing jobs with their
  URLs. Stop. No merge.
- `none`: say the forge ran no pipeline for the commit. Merging then needs the user's
  approval given with that knowledge.
- Deadline passed: say it is still running after `average` + 15 minutes. Stop.

## 5. Approval gate
Approval is an explicit statement ("I approved this PR" / "I approved this"). A merge
method alone is not approval. Once approved, do not ask again.
Before merging, check without asking: PR is open; the pipeline for `REVIEWED_SHA` is
`success` (jobs marked allowed-to-fail may fail); remote `$BRANCH` and local `$BRANCH`
both point at `REVIEWED_SHA`. Any failure: stop.

## 6. Merge method gate
Offer exactly: **Merge FF-ONLY**, **Merge with Commit**, **Squash**. Use a choice already
made, once approved; otherwise ask.

## 7. Merge locally, then push
Never merge in the forge (no `glab mr merge`, `gh pr merge`, `tea pr merge`, no button).
1. Find the worktree with `$TARGET` checked out (`git worktree list`). Stop if it is
   dirty. If it is behind `$REMOTE/$TARGET` after `git fetch $REMOTE`, fast-forward it
   with `git merge --ff-only $REMOTE/$TARGET`; stop if that fails.
2. Check the identity (Inputs). If the worktree's config differs from the policy
   identity, run every commit with `GIT_AUTHOR_NAME/EMAIL` and `GIT_COMMITTER_NAME/EMAIL`
   set on the command line to the policy identity.
3. Integrate `REVIEWED_SHA` (the SHA, not the branch name) with the chosen method:
   - FF-ONLY: `git merge --ff-only $REVIEWED_SHA`. On failure, stop. Never force.
   - Merge with Commit: `git merge --no-ff $REVIEWED_SHA -m "<message naming the PR>"`.
   - Squash: `git merge --squash $REVIEWED_SHA`, then `git commit` with a message naming
     the PR.
   The message names the PR with the forge's reference form (`!N` on GitLab, `#N` on
   GitHub and Gitea) so the forge links them.
4. `git push $REMOTE $TARGET`. Stop if rejected.
5. Re-read the PR state. After FF-ONLY or Merge with Commit the forge sees the head
   commit land on `$TARGET` and marks the PR merged by itself; wait a few seconds for
   that. After a squash it cannot, so close it with the forge CLI, with a comment naming
   the squash commit. Never close a PR the forge already marked merged.

## 8. Delete the remote branch
```
git push $REMOTE :$BRANCH --force-with-lease=$BRANCH:$REVIEWED_SHA
```
Deletes only if the remote branch is still at `REVIEWED_SHA`. If the lease check fails,
stop and report. Leave the local branch alone.
