# Nextflow Agent Skills

[![skills.sh](https://skills.sh/b/nextflow-io/agent-skills)](https://skills.sh/nextflow-io/agent-skills)

Agent skills for Nextflow and nf-core bioinformatics workflows.

## Skills

- [`install-nextflow`](./skills/install-nextflow) — Install or upgrade Nextflow (and Java 17+ via SDKMAN if needed)
- [`create-workflow`](./skills/create-workflow) — Create Nextflow pipelines by composing nf-core modules
- [`run-module`](./skills/run-module) — Run Nextflow modules natively using the `nextflow module` command
- [`launch-workflow`](./skills/launch-workflow) — Launch workflow executions on Seqera Platform

## Hooks

- **nextflow lint** — a `PostToolUse` hook runs `nextflow lint` on any `.nf` or `.config` file Claude writes or edits, feeding errors back so they get fixed automatically. Requires `nextflow` on `PATH`; it skips silently if Nextflow isn't installed.

## Installation

Install the skills with [`skills.sh`](https://skills.sh):

```bash
npx skills@latest add nextflow-io/agent-skills
```

Pick the skills you want and the coding agents you want to install them on. The installer supports Claude Code, Codex, Cursor, and other agents that follow the skills convention.

For skills that require the Seqera MCP (e.g. `launch-workflow`), make sure the [Seqera MCP server](https://mcp.seqera.io/mcp) is configured for your agent.

### Claude Code plugin marketplace

This repo is also a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins). Add it and install the `nextflow` plugin from within Claude Code:

```
/plugin marketplace add nextflow-io/claude-plugin
/plugin install nextflow@nextflow
```

## Local Development

To test the plugin locally without installing:

```bash
claude --plugin-dir /path/to/claude-plugin
```

## Requirements

- A coding agent that supports agent skills (e.g. Claude Code, Codex, Cursor)
- [Nextflow](https://nextflow.io) **26.04 or later** (you can use the `install-nextflow` skill to install it)

## License

Apache-2.0
