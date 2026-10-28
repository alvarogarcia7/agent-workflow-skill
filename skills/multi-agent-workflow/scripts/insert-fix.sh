#!/usr/bin/env bash
# Phase 3 history surgery: a pipeline went RED on commit <red>; the fix is committed on <fix-branch> (created from <red>).
# Rebuild the integration branch as   ... -> <red> -> <fix> -> (everything that came after <red>)   so every commit after the fix is
# verified on top of it:   Green -> Green -> Red -> Fix -> Green2 -> Green3.
# Usage: insert-fix.sh <red-sha> <fix-branch> <integration-branch> [--push]
# Rewrites history AFTER <red> on <integration-branch>: only the Phase 3 loop may do this, holding the push lock, and then every
# worker rebases onto the new tip. --push uses --force-with-lease against the remote branch (never plain --force).
set -eu
red="$1"; fix="$2"; branch="$3"; push="${4:-}"
git merge-base --is-ancestor "$red" "$branch"      || { echo "$red is not in $branch"; exit 1; }
git merge-base --is-ancestor "$red" "$fix"         || { echo "$fix must be created from $red"; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "working tree not clean"; exit 1; }
git rev-parse --verify "$fix" >/dev/null
old_tip=$(git rev-parse "$branch")
git checkout -q "$branch"
git rebase --onto "$fix" "$red" "$branch" || { echo "conflict: resolve, git rebase --continue, then re-run the local checks"; exit 1; }
echo "old tip: ${old_tip:0:9}  new tip: $(git rev-parse --short HEAD)"; git log --oneline "${red}~0..$branch" | cat
if [ "$push" = "--push" ]; then
  remote="${REMOTE:-origin}"; git push --force-with-lease="$branch:$old_tip" "$remote" "$branch:$branch"
fi
