# Agent brief (copy, fill, send)

You are agent <name> on <repository>. <One sentence goal.>

**Read first**: CLAUDE.md/AGENTS.md, the decision log (ids: <D-xx..D-yy>), the tasks `<ids>` (`backlog task view <id> --plain`), the code you will touch: <paths>.

**You own** (edit freely): <files/packages>. **Do not edit**: <files owned by other agents>. Shared files: <one-line mount only, rebase carefully>.

**Setup**: your worktree `<path>` (branch `<name>`), ports API `<port>` / UI `<port>`, env vars for tests: <list all base-URL variables>.

**Task loop**: claim with `backlog task edit <id> -a @<name> -s "In Progress"`; implement; write tests + walkthrough; verify locally; commit with the task id; push with `scripts/safe-push.sh`; start the next task. Never edit task files directly, use the CLI.

**Verification recipe**: <CI-exact commands> ; UI tests through `scripts/heavy.sh ... --workers=2`.

**Decisions**: settle ambiguities yourself; log them in the decision log under ids <block>; do not ask the user.

**Out of bounds**: tasks owned by others: <ids>. Never force-push, never `pkill -f`, never poll the CI API (read `ci-status.json`).

**Report** (short): what is done and where, evidence (tests, pipeline id), what is left, anything for the coordinator.
