---
name: migrate-nextflow-code
description: Migrate Nextflow pipeline code to newer language requirements. Use when fixing strict syntax errors, running `nextflow lint` to detect and fix errors, migrating from the `publishDir` directive to workflow outputs (the `output {}` block), or adding static typing (typed processes/workflows, records, typed params). Currently covers the strict syntax, workflow outputs, and static typing migrations.
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
---

# Migrate Nextflow Code

Migrate Nextflow pipeline code to satisfy newer language requirements. Each migration is detection-driven: a tool reports what must change, you apply behavior-preserving fixes, then re-run the tool until it is clean.

**Requires Nextflow 26.04 or later** (for the `nextflow lint` command and the strict syntax parser, which is the default from 26.04 onward).

**nf-core pipelines — check the template version before starting.** If the pipeline has a `.nf-core.yml`, check which version of nf-core/tools last generated its template. If `nf_core_version` is unspecified or less than 3.0.0, **stop**. Tell the user to upgrade their template first (`nf-core pipelines sync`) before attempting any code migrations. This will resolve syntax errors in the template code and provide a cleaner baseline.

## How to use this skill

This SKILL.md is an **index**. Identify which migration the user needs from the table below, then **read the matching reference file** for the full detect → fix → verify procedure before doing any work. Each reference file is self-contained.

| Migration | Use when the user… | Read this file |
|-----------|--------------------|----------------|
| **Strict syntax** | …has strict syntax errors, or asks to run `nextflow lint` to find and fix errors | [`references/strict-syntax.md`](references/strict-syntax.md) |
| **Static typing** | …wants to add static types — typed process/workflow inputs and outputs, records (replacing tuples), or typed params | [`references/static-typing.md`](references/static-typing.md) |
| **Workflow outputs** | …wants to replace `publishDir` directives with workflow outputs — a top-level `output {}` block and a `publish:` section in the entry workflow | [`references/workflow-outputs.md`](references/workflow-outputs.md) |

If the request matches no row, tell the user which migrations are currently supported rather than improvising.

If the request covers multiple migrations, recommend performing only the first matching migration in the table. The order is also a dependency order: strict syntax -> static typing -> workflow outputs. Do not try to perform multiple migrations at the same time.

## Shared principles (all migrations)

These hold regardless of which reference file you load:

1. **Detect before editing** — run the migration's detection tool (e.g. `nextflow lint`) and work from its actual output. Never guess at what needs changing.
2. **Preserve behavior** — a migration adapts code to new language requirements; it is not a refactor. Apply the smallest change that resolves each issue and leave unrelated logic alone.
3. **Loop until clean** — re-run the detection tool after each batch of fixes and repeat until it reports nothing.
4. **Verify** — run the project's tests (`nf-test test`, or `nextflow run . -profile test,docker`) to confirm behavior is unchanged before declaring the migration done.
