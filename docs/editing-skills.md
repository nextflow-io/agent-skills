# Editing skills

## Structure

- One skill per `skills/<name>/`; the directory name matches frontmatter `name:`.
- On-demand material goes in `skills/<name>/references/*.md`. Shared executables go in top-level `scripts/`, referenced as `${CLAUDE_PLUGIN_ROOT}/scripts/...`.
- `description:` is the trigger text: state *when* to invoke. `allowed-tools:` gates tool use: add a tool there before relying on it.
- Each skill ends with a numbered **Critical Rules** section restating its non-negotiable behaviors; new behavioral requirements go there.

## Cross-skill dependencies

When you change one of these, update every skill that repeats it:

- `create-workflow` delegates to `run-module` via the `Skill` tool; see its delegation table.
- `launch-workflow` requires the Seqera MCP (`mcp__seqera__*`, declared in `.mcp.json`).
- All skills require **Nextflow 26.04+**, which `install-nextflow` enforces. Each skill states its own reason; only the version must match.
- The Wave+Conda `nextflow.config` block appears in `run-module` and `create-workflow`.

## Domain conventions

- **Registry vs nf-core**: modules come from the **Nextflow Registry**; `nf-core` is one namespace in it (e.g. `nf-core/fastqc`).
- **Module testing**: test a single module with `nextflow module run` / `nextflow module view`. `run-module` and `create-workflow` forbid writing wrapper workflows for this; keep that wording emphatic.
- **Includes**: prefer Nextflow-managed includes (`from 'nf-core/module'`) over local paths (`from './module.nf`).
- **Calendar versioning**: `YY.MM.PATCH`, so `26.04.0` is newer than `25.10.1`. Pin with `NXF_VER`.
