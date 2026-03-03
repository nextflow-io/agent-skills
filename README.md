# Seqera Claude Code Plugin for Nextflow

Claude Code skills for Nextflow and nf-core bioinformatics workflows, powered by the Seqera MCP server.

## Skills

| Skill | Description |
|-------|-------------|
| `nextflow-workflow-writer` | Create Nextflow pipelines by composing nf-core modules |
| `run-nfcore-module` | Execute nf-core modules with proper configuration |
| `nextflow-run-module` | Run Nextflow modules natively using `nextflow module` commands |
| `install-nfcore-module` | Install nf-core modules into your project |
| `container-provisioner` | Provision containers on-the-fly using Seqera Wave |

## Installation

### 1. Add the marketplace

```bash
/plugin marketplace add seqeralabs/claude-plugin
```

### 2. Install the plugin

```bash
/plugin install seqera@seqeralabs-claude-plugin
```

### 3. Approve the Seqera MCP server

When prompted, approve the Seqera MCP server connection to enable the skills.

## Usage

Once installed, use the skills with the `seqera:` namespace:

```bash
/seqera:nextflow-workflow-writer
/seqera:run-nfcore-module
/seqera:nextflow-run-module
/seqera:install-nfcore-module
/seqera:container-provisioner
```

## Local Development

To test the plugin locally without installing:

```bash
claude --plugin-dir /path/to/claude-plugin
```

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- [Nextflow](https://nextflow.io) (for running workflows)
- [nf-core tools](https://nf-co.re/tools) (for installing modules)

## License

Apache-2.0
