---
name: run-module
description: Run Nextflow Registry modules natively using `nextflow module` commands. Use when running, listing, or getting info about Nextflow modules, including process modules (a single tool) and workflow modules (subworkflows that chain several modules).
allowed-tools: Bash, Read, Glob
---

# Run Nextflow Modules

Run modules from the [Nextflow Registry](https://registry.nextflow.io) natively using `nextflow module` commands. Everything is self-contained — no external tools or MCP needed. Modules are installed on-the-fly when run.

Modules are published under namespaces (e.g. `nf-core/fastqc`), and the `nextflow module` commands work with any of them.

**Requires Nextflow 26.04 or later** (for the `nextflow module` commands). Workflow modules require **Nextflow 26.10 or later**.

### Process modules vs workflow modules

A module has a **kind**, reported as `Kind:` by `nextflow module search` and `nextflow module view`:

| Kind | What it is | Example |
|------|------------|---------|
| `Process` | A single process wrapping one tool | `nf-core/star/align` |
| `Workflow` | A named workflow (subworkflow) that chains several modules; its dependencies are installed with it | `nf-core/fastq_align_star` (STAR + samtools sort/index/stats) |

Both kinds are searched, viewed, run, and included the same way. The differences are covered in [Finding Workflow Modules](#finding-workflow-modules) and [Running Workflow Modules](#running-workflow-modules).

## ⛔ NEVER WRITE WRAPPER WORKFLOWS

**If a module fails due to missing arguments or incorrect parameters:**

❌ **WRONG** - Writing a wrapper workflow:
```groovy
// NEVER DO THIS - even if the module fails!
include { FASTQC } from 'nf-core/fastqc'
workflow { FASTQC(Channel.fromPath('*.fq.gz')) }
```

✅ **CORRECT** - Use `nextflow module view` to get the correct parameters:
```bash
nextflow module view nf-core/fastqc
```

**When a module run fails:**
1. Run `nextflow module view <module>` to get the command template
2. Fix the arguments based on the template
3. Re-run with `nextflow module run <module> ...`

**NEVER create a wrapper workflow as a "fix" for missing arguments.**

## Step 1: Search for the Module

Use `nextflow module search` with a natural language term — it performs similarity search on module name, description, and features:

```bash
nextflow module search "quality control"
nextflow module search "alignment"
nextflow module search "variant calling"
nextflow module search "BAM statistics"
```

### Finding Workflow Modules

`nextflow module search` ranks workflow modules below process modules, so they rarely show up in its results. When the task spans several steps (e.g. "align with STAR then sort and index"), also query the registry API with the `kind=Workflow` filter:

```bash
curl -s "https://registry.nextflow.io/api/v1/modules?query=align%20reads%20STAR&kind=Workflow&limit=10" \
  | python3 -c 'import json,sys; [print(r["name"], "-", r["description"]) for r in json.load(sys.stdin)["results"]]'
```

URL-encode spaces in `query` as `%20`. Then inspect any match with `nextflow module view`.

## Step 2: Get Module Info and Run Template

Once you've identified the module, get its detailed info and the command template:

```bash
nextflow module view nf-core/fastqc
```

This returns the module kind, description, inputs, parameters, and the exact run command template. Use this template as the basis for your run command.

For a workflow module, the inputs are the workflow's `take:` declarations (in call order) and the outputs are its `emit:` declarations.

## Step 3: Substitute Template Values and Run

Replace placeholder values in the template with the user's concrete values (file paths, parameters), then execute. No explicit install is needed — modules are fetched on-the-fly:

```bash
nextflow module run nf-core/fastqc \
  --input "/path/to/sample.fq.gz" \
  --outdir results
```

### Container Provisioning with Wave + Conda

Modules require containers for their underlying tools. Configure `nextflow.config` to use Wave + Conda so containers are provisioned on-the-fly from each module's conda packages:

```groovy
wave.enabled = true
wave.strategy = 'conda,container'
docker.enabled = true
```

This avoids the need to manually build or pull container images — Wave provisions them from the module's declared conda dependencies.

### Running Workflow Modules

A workflow module runs with the same `nextflow module run` command, with these differences:

- **It must be typed.** Only workflow modules with typed `take:` inputs can be run directly. Most nf-core workflow modules are untyped and fail with:
  ```
  Workflow `FASTQ_ALIGN_STAR` cannot be executed directly because it is not typed
  ```
  `nextflow module view` still prints a usage template for untyped workflow modules, so this error is the signal. The failed run has already installed the module and its dependencies under `./modules/`. It is **not** a missing-argument problem and **not** a reason to write a wrapper workflow. When invoked from `create-workflow` Step 3, follow that skill's instruction (defer to its Step 4). Otherwise, stop and tell the user the workflow module cannot be run on its own, then offer:
  - running its constituent process modules one by one with `nextflow module run`. They are listed under `requires.modules` in `./modules/<namespace>/<name>/meta.yml`, and any listed workflow module has its own nested `meta.yml` to expand. Or
  - using it inside a pipeline via the `create-workflow` skill.
- **Channel inputs take a samplesheet.** A `Channel<...>` input accepts a CSV, JSON, or YAML samplesheet path; each row becomes one channel item. A `Value<...>` input accepts a single value (e.g. a file path).
- **Outputs are not published.** Each emitted output is reported with its work directory path; nothing is copied to `--outdir`.

## Commands Reference

| Command | Description |
|---------|-------------|
| `nextflow module search <term>` | Similarity search by name/description/feature |
| `nextflow module view <name>` | Detailed info about the module and how to run it |
| `nextflow module run <name> [options]` | Run a module (installed on-the-fly) |
| `nextflow module list` | List installed modules with their version and kind |

## Examples

### Single-end FASTQ Quality Control
```bash
# 1. Search
nextflow module search "quality control"

# 2. Get the template
nextflow module view nf-core/fastqc

# 3. Run with concrete values
nextflow module run nf-core/fastqc \
  --input "data/sample.fq.gz" \
  --outdir results_fastqc
```

### Paired-end Alignment
```bash
# 1. Search
nextflow module search "bwa alignment"

# 2. Get the template
nextflow module view nf-core/bwa/mem

# 3. Run with concrete values
nextflow module run nf-core/bwa/mem \
  --input "data/reads_1.fq.gz,data/reads_2.fq.gz" \
  --reference "data/genome.fa" \
  --outdir results_bwa
```

## Complete Workflow: Search → Info → Run

1. **Search** for the module:
   ```bash
   nextflow module search "quality control for FASTQ"
   ```

2. **Get info** and run template:
   ```bash
   nextflow module view nf-core/fastqc
   ```

3. **Substitute** template placeholders with actual values from the user's data

4. **Run** the module:
   ```bash
   nextflow module run nf-core/fastqc \
     --input "data/sample.fq.gz" \
     --outdir results
   ```

5. **Process output** — Read the stdout, summarize key results, and suggest the logical next step to the user

## Critical Rules

1. **SEARCH FIRST** — Always use `nextflow module search` to find the right module
2. **GET THE TEMPLATE** — Always run `nextflow module view` before running a module
3. **SUBSTITUTE TEMPLATE VALUES** — Replace all placeholders with concrete values from the user's data
4. **NEVER write wrapper workflows** — If a run fails, use `nextflow module view` to get correct args
5. **NEVER guess parameters** — Always get them from the info template
6. **Expand wildcards first** — Use `ls data/*.fq` then comma-separate results
7. **Quote multi-file inputs** — `--input "file1,file2,file3"`
8. **Use absolute paths** when possible
9. **ALWAYS PROCESS STDOUT OUTPUT** — After a successful run, present a summary and suggest the logical next step
10. **CHECK THE KIND** — `nextflow module view` reports `Kind: Process` or `Kind: Workflow`; for multi-step tasks, also look for workflow modules via the registry API `kind=Workflow` filter
11. **UNTYPED WORKFLOW MODULES CANNOT RUN DIRECTLY** — on "cannot be executed directly because it is not typed", stop and offer the alternatives in [Running Workflow Modules](#running-workflow-modules); never write a wrapper workflow

## When Module Run Fails

**DO NOT write a wrapper workflow.** Instead:

1. Run `nextflow module view nf-core/<module>`
2. Compare the template with your command to find discrepancies
3. Fix your `nextflow module run` command with correct arguments
4. Re-run the corrected command

## Step 4: Process Run Output (MANDATORY)

The `nextflow module run` command prints its output to stdout. After a module run, you MUST:

1. **Read the stdout output** from the run command
2. **Present a clear summary** of the results to the user — highlight key metrics, status, and any warnings or errors
3. **Infer the next step** — Based on the output and the module that was run, suggest what the user might want to do next. Examples:
   - After `fastqc`: "Quality scores look good. Would you like to proceed to alignment with `bwa/mem`?"
   - After `bwa/mem`: "Alignment complete. Would you like to sort the BAM with `samtools/sort` or get stats with `samtools/stats`?"
   - After `fastp`: "Trimming done. Would you like to align the trimmed reads?"

Always frame next-step suggestions as questions to the user.

Only list or inspect output files in the work directory if the module or user specifically requires it — do not do this by default.
