# Nextflow Agent Skills

Agent skills for building and running Nextflow pipelines with modules from the [Nextflow Registry](https://registry.nextflow.io).

The Nextflow Registry is the central place to discover and share Nextflow modules and plugins. Modules are published under namespaces — [nf-core](https://nf-co.re) is the most prominent — and these skills work with modules from any of them.

These skills follow the [Agent Skills](https://agentskills.io/specification) specification, so they can be used by any skills-compatible agent, including Claude Code, Codex CLI, OpenCode, and Cursor.

## Skills

- [`install-nextflow`](./skills/install-nextflow) — Install or upgrade Nextflow (and Java 17+ via SDKMAN if needed)
- [`create-workflow`](./skills/create-workflow) — Create Nextflow pipelines by composing modules from the Nextflow Registry
- [`run-module`](./skills/run-module) — Run Nextflow Registry modules natively using the `nextflow module` command
- [`launch-workflow`](./skills/launch-workflow) — Launch pipeline executions on Seqera Platform

## Language server

The plugin also wires up the official [Nextflow language server](https://github.com/nextflow-io/language-server) as a [Claude Code LSP server](https://code.claude.com/docs/en/plugins-reference#lsp-servers). When you edit a `.nf` script or `nextflow.config`, the agent gets real-time diagnostics, go-to-definition, and hover info — so mistakes surface as you write rather than only when the pipeline runs.

The launcher (`scripts/nextflow-language-server.sh`) resolves the server in this order:

1. a native `nlsp` binary on your `PATH` (no JVM startup cost), then
2. a jar pointed to by `$NEXTFLOW_LSP_JAR` (e.g. a local development build), then
3. the official `language-server-all.jar` — following the same convention as the [Nextflow VS Code extension](https://github.com/nextflow-io/vscode-language-nextflow): it resolves the latest patch release of the tracked minor version from GitHub and caches it at `~/.nextflow/lsp/v26.04/v26.04.<patch>.jar`, reusing the cached jar on later starts.

The jar path needs Java 17+ (the same prerequisite as the `install-nextflow` skill). Set `NEXTFLOW_LSP_VERSION` to track a different minor version (default `26.04`), and `GITHUB_TOKEN` to avoid GitHub API rate limits.

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
claude --plugin-dir /path/to/agent-skills
```

## Requirements

- A coding agent that supports agent skills (e.g. Claude Code, Codex, Cursor)
- [Nextflow](https://nextflow.io) **26.04 or later** (you can use the `install-nextflow` skill to install it)

## License

Apache-2.0
