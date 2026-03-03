---
name: nextflow-run-module
description: Run Nextflow modules natively using `nextflow module` commands. Use when running, listing, installing, or getting info about Nextflow modules without the nf-core CLI.
allowed-tools: Bash, Read, Glob, mcp__seqera__search_nfcore_module, mcp__seqera__describe_nfcore_module
---

# Run Nextflow Modules

Run modules natively using `nextflow module` commands. Unlike nf-core modules, these do not require a separate CLI tool — everything is managed by Nextflow itself.

## ⛔ NEVER WRITE WRAPPER WORKFLOWS

**If a module fails due to missing arguments or incorrect parameters:**

❌ **WRONG** - Writing a wrapper workflow:
```groovy
// NEVER DO THIS - even if the module fails!
include { FASTQC } from './modules/nf-core/fastqc/main'
workflow { FASTQC(Channel.fromPath('*.fq.gz')) }
```

✅ **CORRECT** - Use Seqera MCP to get the correct parameters, then use `nextflow module info`:
```
mcp__seqera__describe_nfcore_module(module_name="nf-core/fastqc")
```
```bash
nextflow module info nf-core/fastqc
```

**When a module run fails:**
1. Call `mcp__seqera__describe_nfcore_module` to get correct input/parameter schema
2. Run `nextflow module info <module>` to get the command template
3. Fix the arguments based on the template and schema
4. Re-run with `nextflow module run <module> ...`

**NEVER create a wrapper workflow as a "fix" for missing arguments.**

## Step 1: Discover Module via Seqera MCP (MANDATORY)

**Before running ANY module, you MUST search for it using Seqera MCP first.**

Use `mcp__seqera__search_nfcore_module` with natural language:
- "quality control for FASTQ files"
- "BAM file statistics"
- "sequence alignment"
- "variant calling"

```
mcp__seqera__search_nfcore_module(query="quality control for FASTQ")
```

Then get detailed info:
```
mcp__seqera__describe_nfcore_module(module_name="nf-core/fastqc")
```

## Step 2: Configure the Module Registry

Before running any module commands, ensure a `nextflow.config` file exists in the working directory with the module registry configured:

```groovy
registry {
    url = 'https://registry-dev.nextflow.io/api'
}
```

If the file doesn't exist, create it. If it exists, add the `registry` block if not already present.

## Step 3: Get the Command Template

Run `nextflow module info` to get the exact run template with expected options:

```bash
nextflow module info nf-core/fastqc
```

This returns a command template showing all available options and their expected values. Use this template as the basis for your run command.

## Step 4: Substitute Template Values and Run

Replace placeholder values in the template with the user's concrete values (file paths, parameters), then execute:

```bash
nextflow module run nf-core/fastqc \
  --input "/path/to/sample.fq.gz" \
  --outdir results \
```

## Full Lifecycle Commands

### List available modules
```bash
nextflow module list
```

### Get module info and run template
```bash
nextflow module info nf-core/<MODULE_NAME>
```

### Install a module locally
```bash
nextflow module install nf-core/<MODULE_NAME>
```

### Run a module
```bash
nextflow module run nf-core/<MODULE_NAME> [options]
```

## Examples

### Single-end FASTQ Quality Control
```bash
# 1. Get the template
nextflow module info nf-core/fastqc

# 2. Run with concrete values
nextflow module run nf-core/fastqc \
  --input "data/sample.fq.gz" \
  --outdir results_fastqc
```

### Paired-end Alignment
```bash
# 1. Get the template
nextflow module info nf-core/bwa/mem

# 2. Run with concrete values
nextflow module run nf-core/bwa/mem \
  --input "data/reads_1.fq.gz,data/reads_2.fq.gz" \
  --reference "data/genome.fa" \
  --outdir results_bwa
```

### With Additional Parameters
```bash
nextflow module run nf-core/fastp \
  --input "data/R1.fq,data/R2.fq" \
  --skip_trimming \
  --outdir results_fastp
```

## Complete Workflow: Discover → Configure → Info → Run

1. **Discover** module using Seqera MCP:
   ```
   mcp__seqera__search_nfcore_module(query="quality control for FASTQ")
   mcp__seqera__describe_nfcore_module(module_name="nf-core/fastqc")
   ```

2. **Configure** the module registry in `nextflow.config`:
   ```groovy
   registry {
       url = 'https://registry-dev.nextflow.io/api'
   }
   ```

3. **Get template** using native Nextflow command:
   ```bash
   nextflow module info nf-core/fastqc
   ```

4. **Substitute** template placeholders with actual values from the user's data

5. **Run** the module:
   ```bash
   nextflow module run nf-core/fastqc \
     --input "data/sample.fq.gz" \
     --outdir results
   ```

6. **Process output** — Read the stdout, summarize key results, and suggest the logical next step to the user

## Critical Rules

1. **CALL SEQERA MCP FIRST** - Always call `mcp__seqera__search_nfcore_module` or `mcp__seqera__describe_nfcore_module` BEFORE attempting to run any module
2. **CONFIGURE REGISTRY** - Ensure `nextflow.config` contains the `registry { url = 'https://registry-dev.nextflow.io/api' }` block before running any module commands
3. **USE `nextflow module info`** - Always get the command template before running
3. **SUBSTITUTE TEMPLATE VALUES** - Replace all placeholders with concrete values from the user's data
5. **NEVER write wrapper workflows** - If a run fails, call MCP and `nextflow module info` again to get correct args
6. **NEVER guess parameters** - Always get them from the template or MCP response
8. **Expand wildcards first** - Use `ls data/*.fq` then comma-separate results
9. **Quote multi-file inputs** - `--input "file1,file2,file3"`
10. **Use absolute paths** when possible
11. **ALWAYS PROCESS STDOUT OUTPUT** - After a successful run, read the stdout, present a summary to the user, and suggest the logical next step

## When Module Run Fails

**DO NOT write a wrapper workflow.** Instead:

1. Call `mcp__seqera__describe_nfcore_module(module_name="nf-core/<module>")`
2. Run `nextflow module info nf-core/<module>`
3. Compare the template with your command to find discrepancies
4. Fix your `nextflow module run` command with correct arguments
5. Re-run the corrected command

## Step 5: Process Run Output (MANDATORY)

The `nextflow module run` command prints its output to stdout. After a module run, you MUST:

1. **Read the stdout output** from the run command
2. **Present a clear summary** of the results to the user — highlight key metrics, status, and any warnings or errors
3. **Infer the next step** — Based on the output and the module that was run, suggest what the user might want to do next. Examples:
   - After `fastqc`: "Quality scores look good. Would you like to proceed to alignment with `bwa/mem`?"
   - After `bwa/mem`: "Alignment complete. Would you like to sort the BAM with `samtools/sort` or get stats with `samtools/stats`?"
   - After `fastp`: "Trimming done. Would you like to align the trimmed reads?"

Always frame next-step suggestions as questions to the user.

Only list or inspect output files in the work directory if the module or user specifically requires it — do not do this by default.
