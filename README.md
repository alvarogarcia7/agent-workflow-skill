# multi-agent-workflow

A [Claude Code](https://claude.com/claude-code) skill for running a large backlog with **one coordinator and several parallel
agents/subagents**: a [Backlog.md](https://github.com/MrLesk/Backlog.md) task loop, design-consult agents, a decision log,
file ownership and git worktrees, local verification, and a **push/CI flow that never overloads CI** (agents push with
`ci.skip`; one trigger loop runs one pipeline at a time and publishes a status file everybody reads instead of polling).

It is project-independent. Project specifics (verification commands, ports, test tools) go in your brief and a short
`WORKFLOW.md` in your repository.

## Contents

```
skills/multi-agent-workflow/
  SKILL.md                 the playbook
  templates/               agent brief, decision entry, queue file
  scripts/
    safe-push.sh           lock + rebase-if-behind + push with -o ci.skip
    ci-trigger.sh          one CI pipeline at a time for the MR head; writes ci-status.json and ci-failures.log (GitLab)
    heavy.sh               machine-wide limit of N concurrent heavy jobs (flock)
    keep-both.py           resolve conflict markers in append-only logs by keeping both sides
    env.example            configuration
```

## Install

Copy `skills/multi-agent-workflow` into your project's `.claude/skills/` (or `~/.claude/skills/` for all projects), copy
the scripts where all agents can run them, and create `.agent-workflow.env` from `scripts/env.example`.

## Requirements

`git`, `bash`, `flock`, `python3`; `glab` (authenticated) for `ci-trigger.sh` (adapt the three `api` calls with `gh api` for
GitHub Actions); the `backlog` CLI for the task workflow.

## Status

Extracted from a real multi-agent run (a full-stack web app, ~100 backlog tasks, six parallel agents). Add a `LICENSE`
before publishing.
