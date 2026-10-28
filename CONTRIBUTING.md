# Contributing

- Run `tests/run.sh` before sending a change; it uses `tests/fake-glab/glab`, a shell script driven by fixture files (see its header), so no network or GitLab is needed. Add a scenario for every script change.
- Check syntax: `bash -n` on every script, `python3 -m py_compile` on `keep-both.py`. Run `shellcheck` if you have it (also a good CI job).
- Keep the skill project-independent: no project names, task-id prefixes, fixed ports or personal paths. Keep SKILL.md short; put detail in `references/`.
- Update `CHANGELOG.md`.
- Future idea: package as a Claude Code plugin (`.claude-plugin/plugin.json`) so it installs with `/plugin install`; not done because the manifest schema was not verified.
