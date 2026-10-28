# multi-agent-workflow

A [Claude Code](https://claude.com/claude-code) skill for running a large backlog with **one coordinator and several parallel
agents/subagents**: a [Backlog.md](https://github.com/MrLesk/Backlog.md) task loop, design-consult agents, a decision log,
file ownership and git worktrees, local verification, and a **push/CI flow that never overloads CI** (agents push with
`ci.skip`; one trigger loop runs one pipeline at a time and publishes a status file everybody reads instead of polling).

It is project-independent. Project specifics (verification commands, ports, test tools) go in your brief and a
`WORKFLOW.md` in your repository (template included).

## Contents

```
skills/multi-agent-workflow/
  SKILL.md        the playbook
  references/     ci-gitlab.md, ci-github.md, parity-loop.md, lessons.md
  templates/      WORKFLOW.md, agent-brief, handover, design-consult-brief, ci-report, decision-entry, queue, finalize.sh
  scripts/        lib.sh, safe-push.sh, ci-trigger.sh (GitLab), heavy.sh, keep-both.py, env.example
tests/            run.sh and a fake glab (fixture driven)
```

## Requirements

- `git`, `bash`, `python3`, `flock` (Linux util-linux; macOS: `brew install flock`, otherwise `heavy.sh` and `safe-push.sh` fall back to mkdir locks).
- The `backlog` CLI for the task workflow: `npm i -g backlog.md`.
- `glab` (authenticated) for `ci-trigger.sh`. Creating MR pipelines needs a token with `api` scope and the Developer role (plus push/merge rights if the source branch is protected), and `.gitlab-ci.yml` must define jobs for `merge_request_event`.
- A test runner that records video if you want the walkthroughs (SKILL.md section 5).

## Install

1. Copy `skills/multi-agent-workflow` into your project's `.claude/skills/` (or `~/.claude/skills/` for all projects).
2. Put the scripts where all agents can run them.
3. Create `.agent-workflow.env` from `scripts/env.example` in the main checkout (found from every git worktree), and
   `export AGENT_WORKFLOW_ENV=/abs/path/.agent-workflow.env` if you keep it elsewhere. `BRANCH` is required.
4. Copy `templates/WORKFLOW.md` to your repository and fill it in.

## CI providers

GitLab only out of the box. On GitHub Actions: (1) set `on:` to `workflow_dispatch` (plus `pull_request` only if you accept one run per push) and add `concurrency: {group: integration, cancel-in-progress: false}`; (2) set `PUSH_OPTS=""` (no `-o ci.skip`, which does nothing on GitHub and makes remotes without push options reject the push); (3) the trigger calls `gh workflow run <file> --ref "$BRANCH"` and reads `gh run list --workflow <file> --branch "$BRANCH" --json databaseId,status,conclusion,headSha`. `[skip ci]` in commit messages is an alternative but must be in every pushed head commit. A sketch is in `skills/multi-agent-workflow/references/ci-github.md`.

## Tests

`tests/run.sh` (no network, no real GitLab).

## Status and license

Extracted from a real multi-agent run (a full-stack web app, ~100 backlog tasks, six parallel agents).
License: to be chosen by the repository owner. Add a `LICENSE` before publishing.


## Phase pipeline

`MULTI_AGENT_DEV_SKILL.md` describes the four-phase pipeline (Development → Review → Push → Comparison), each phase a Ralph Wiggum loop connected by FIFO mailboxes. Skills: `skills/mad-phase-1-development`, `mad-phase-2-review`, `mad-phase-3-push`, `mad-phase-4-comparison`; scripts in `skills/multi-agent-workflow/scripts/` (`mailbox.sh`, `ralph-loop.sh`, `insert-fix.sh`).
