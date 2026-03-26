# Nextflow Claude Code Plugin

Claude Code skills for Nextflow and nf-core bioinformatics workflows, powered by the Seqera MCP server.

## Skills

| Skill | Description |
|-------|-------------|
| `create-workflow` | Create Nextflow pipelines by composing nf-core modules |
| `run-module` | Run Nextflow modules natively using `nextflow module` commands |
| `launch-workflow` | Launch workflow executions on Seqera Platform |
| `create-container` | Provision containers on-the-fly using Seqera Wave |

## Installation

### 1. Add the marketplace

```bash
/plugin marketplace add nextflow-io/claude-plugin
```

### 2. Install the plugin

```bash
/plugin install nextflow@nextflow-io-claude-plugin
```

### 3. Approve the Seqera MCP server

When prompted, approve the Seqera MCP server connection to enable the skills.

## Usage

Once installed, use the skills with the `nextflow:` namespace:

```bash
/nextflow:create-workflow
/nextflow:run-module
/nextflow:launch-workflow
/nextflow:create-container
```

## Local Development

To test the plugin locally without installing:

```bash
claude --plugin-dir /path/to/claude-plugin
```

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- [Nextflow](https://nextflow.io) (for running workflows)

## License

Apache-2.0
