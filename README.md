# Nextflow Agent Skills

Agent skills for Nextflow and nf-core bioinformatics workflows.

These skills follow the [Agent Skills](https://agentskills.io/specification) specification, so they can be used by any skills-compatible agent, including Claude Code, Codex CLI, OpenCode, and Cursor.

## Skills

- [`install-nextflow`](./skills/install-nextflow) — Install or upgrade Nextflow (and Java 17+ via SDKMAN if needed)
- [`create-workflow`](./skills/create-workflow) — Create Nextflow pipelines by composing nf-core modules
- [`run-module`](./skills/run-module) — Run Nextflow modules natively using the `nextflow module` command
- [`launch-workflow`](./skills/launch-workflow) — Launch workflow executions on Seqera Platform

## Installation

### Claude Code

```

/plugin marketplace add nextflow-io/agent-skills
/plugin install nextflow@nextflow-io-agent-skills
```

When prompted, approve the Seqera MCP server connection to enable the skills. Claude Code automatically keeps your skills up to date.

### GitHub CLI

If you use the [GitHub CLI](https://cli.github.com/) (v2.90.0+), you can install skills with [`gh skill`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/):

```bash
gh skill install nextflow-io/agent-skills
```

Pick the skills you want and the coding agents you want to install them on. The installer supports Claude Code, Codex, Cursor, and other agents that follow the skills convention.

For skills that require the Seqera MCP (e.g. `launch-workflow`), make sure the [Seqera MCP server](https://mcp.seqera.io/mcp) is configured for your agent.

You can update installed skills using `gh skill update`:

```bash
# Check for updates interactively
gh skill update

# Update all installed skills
gh skill update --all
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
