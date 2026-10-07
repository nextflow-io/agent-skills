# AGENTS.md

A Claude Code plugin of agent skills ([Agent Skills spec](https://agentskills.io/specification)) for building and running Nextflow pipelines with modules from the [Nextflow Registry](https://registry.nextflow.io). The deliverable is `skills/*/SKILL.md`; there is no build.

- Load locally: `claude --plugin-dir .`
- Type-check Nextflow code: `scripts/nextflow-typecheck.sh` (`nextflow lint` only checks syntax).
- `.claude/commands/` is repo-local dev tooling (e.g. `/eval`), not shipped to plugin users.
- Releasing: bump `version` in `.claude-plugin/plugin.json`.
- After editing `.github/workflows/`, run `npx actions-up` and `zizmor`.

Before editing any skill, read [docs/editing-skills.md](docs/editing-skills.md).
