# Nextflow Claude Code Plugin

Nextflow and nf-core bioinformatics workflow skills for AI coding agents. Ships as a native Claude Code plugin (auto-updating via the marketplace) and as a single-binary install for Codex, Cursor, Gemini CLI, GitHub Copilot, Goose, Windsurf, and OpenCode via the included [`install.sh`](#other-agents).

## Skills

| Skill | Description |
|-------|-------------|
| `install-nextflow` | Install or upgrade Nextflow (and Java 17+ via SDKMAN if needed) |
| `create-workflow` | Create Nextflow pipelines by composing nf-core modules |
| `run-module` | Run Nextflow modules natively using `nextflow module` commands |
| `launch-workflow` | Launch workflow executions on Seqera Platform |

## Installation

### Claude Code

The native plugin marketplace gives you automatic updates whenever the upstream skills change.

1. Add the marketplace:
   ```bash
   /plugin marketplace add nextflow-io/claude-plugin
   ```
2. Install the plugin:
   ```bash
   /plugin install nextflow@nextflow-io-claude-plugin
   ```
3. Approve the Seqera MCP server when prompted, to enable the skills.

Once installed, invoke the skills with the `nextflow:` namespace:

```bash
/nextflow:install-nextflow
/nextflow:create-workflow
/nextflow:run-module
/nextflow:launch-workflow
```

### Other agents

The repo ships an `install.sh` script that copies (or symlinks) the SKILL.md files into the target agent's skills directory. The destination follows each agent's own convention — run `./install.sh --list` to see them all.

| Agent | Default destination | Scope |
|-------|---------------------|-------|
| `codex` | `~/.codex/skills/` | user-wide |
| `gemini` | `~/.gemini/skills/` | user-wide |
| `goose` | `~/.config/goose/skills/` | user-wide |
| `cursor` | `./.cursor/skills/` | project-scoped (requires Cursor nightly) |
| `copilot` | `./.github/skills/` | project-scoped |
| `windsurf` | `./.windsurf/skills/` | project-scoped |
| `opencode` | `./.opencode/skills/` | project-scoped |

```bash
git clone https://github.com/nextflow-io/claude-plugin
cd claude-plugin

./install.sh --list                       # show all supported agents and paths
./install.sh --agent codex                # copy SKILL.md files into the agent's dir
./install.sh --agent gemini --symlink     # symlink so `git pull` propagates updates
./install.sh --agent cursor --dry-run     # preview without changing anything
./install.sh --agent codex --target ~/skills-staging --force
./install.sh --help
```

To update later: `git pull && ./install.sh --agent <name> --force` — or use `--symlink` once and `git pull` is enough.

> The `launch-workflow` skill requires the [Seqera MCP server](https://mcp.seqera.io/mcp). Configure it in your agent before invoking that skill.

## Local Development

To test the plugin locally in Claude Code without installing via the marketplace:

```bash
claude --plugin-dir /path/to/claude-plugin
```

For other agents, point `install.sh` at a scratch directory and inspect the result:

```bash
./install.sh --agent codex --target /tmp/nextflow-skills --force
```

## Requirements

- A coding agent — [Claude Code](https://claude.ai/code), Codex, Cursor, Gemini CLI, or another SKILL.md-compatible harness
- [Nextflow](https://nextflow.io) **26.04.0 or later** (required for `nextflow module` and `nextflow auth`/`nextflow launch` commands)

## Credits

The cross-agent `install.sh` script's CLI shape was inspired by [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/main/scripts/install.sh) (MIT). Credit to its authors.

## License

Apache-2.0
