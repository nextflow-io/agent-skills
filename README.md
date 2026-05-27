# Nextflow Claude Code Plugin

Claude Code skills for Nextflow and nf-core bioinformatics workflows, powered by the Seqera MCP server.

## Skills

| Skill | Description |
|-------|-------------|
| `install-nextflow` | Install or upgrade Nextflow (and Java 17+ via SDKMAN if needed) |
| `create-workflow` | Create Nextflow pipelines by composing nf-core modules |
| `run-module` | Run Nextflow modules natively using `nextflow module` commands |
| `launch-workflow` | Launch workflow executions on Seqera Platform |

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
/nextflow:install-nextflow
/nextflow:create-workflow
/nextflow:run-module
/nextflow:launch-workflow
```

## Hooks

A `PostToolUse` hook runs `nextflow lint` on any `.nf` or `.config` file the plugin writes or edits, feeding errors back so they get fixed automatically. It requires `nextflow` on `PATH` and skips silently when Nextflow isn't installed.

## Local Development

To test the plugin locally without installing:

```bash
claude --plugin-dir /path/to/claude-plugin
```

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- [Nextflow](https://nextflow.io) **26.04.0 or later** (required for `nextflow module` and `nextflow auth`/`nextflow launch` commands)

## License

Apache-2.0
