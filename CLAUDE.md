# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code plugin that bundles **agent skills** for building and running Nextflow pipelines with modules from the [Nextflow Registry](https://registry.nextflow.io). There is no application code, build step, or test suite — the deliverable is the set of `SKILL.md` files, each a Markdown document with YAML frontmatter that instructs an agent how to perform a task.

Skills follow the [Agent Skills specification](https://agentskills.io/specification) so they work in any compatible agent (Claude Code, Codex, Cursor, OpenCode).

## Layout

- `skills/<name>/SKILL.md` — one skill per directory; the directory name must match the `name:` in frontmatter.
- `.claude-plugin/plugin.json` — plugin manifest (name, version, keywords). Bump `version` when releasing.
- `.mcp.json` — declares the `seqera` MCP server (`https://mcp.seqera.io/mcp`) that `launch-workflow` depends on.
- `.lsp.json` — declares the [Nextflow language server](https://github.com/nextflow-io/language-server) as an LSP server, giving the agent live diagnostics/navigation for `.nf` and `.config` files. It runs `scripts/nextflow-language-server.sh`, which prefers a native `nlsp` binary on PATH and otherwise downloads/runs the `language-server-all.jar` (needs Java 17+). When bumping the pinned language-server version, update `VERSION` in that script.

## The four skills and how they relate

- `install-nextflow` — installs/upgrades Nextflow and the Java 17+ prerequisite (via SDKMAN). Other skills require **Nextflow 26.04+**.
- `run-module` — runs a single Registry module via `nextflow module search/view/run`. Self-contained (no MCP).
- `create-workflow` — composes multiple modules into a pipeline. **Delegates to `run-module`** (via the `Skill` tool) to validate each module before composing.
- `launch-workflow` — launches pipelines on Seqera Platform for cloud/HPC execution. **Requires the seqera MCP** (`mcp__seqera__*` tools) — declared in `allowed-tools`.

When editing one skill, check the others for consistency: cross-references (the `Skill` delegation table in `create-workflow`), the shared "Nextflow 26.04+" requirement line, and the Wave+Conda `nextflow.config` block all appear in more than one file and must stay in sync.

## Conventions that recur across skills (preserve these when editing)

- **Terminology**: modules come from the **Nextflow Registry**. `nf-core` is one *namespace* among many (e.g. `nf-core/fastqc`) — don't equate the Registry with nf-core.
- **Never write wrapper workflows to test a single module** — `run-module` and `create-workflow` both forbid this emphatically. Use `nextflow module run` / `nextflow module view` instead. Don't soften this guidance.
- **Module include syntax**: prefer Nextflow-managed includes (`from 'nf-core/module'`, no `./` prefix) over local file paths.
- **Calendar versioning**: Nextflow uses `YY.MM.PATCH`, not semver — `26.04.0` is newer than `25.10.1`. Use `NXF_VER` to pin, `NXF_EDGE` for the edge channel.
- Each skill ends with a numbered **Critical Rules** section that restates its non-negotiable behaviors; new behavioral requirements belong there.

## Editing skills

- Frontmatter `description:` is the trigger text the agent matches against — it must clearly state *when* to invoke the skill. `allowed-tools:` gates which tools the skill may use; add a tool here before relying on it.
- After editing GitHub Actions workflows (if any are added), run `npx actions-up` and `zizmor` to harden them.

## Local testing

```bash
claude --plugin-dir /path/to/agent-skills
```

Loads the plugin without installing it from the marketplace.
