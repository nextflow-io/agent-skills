---
name: run-nfcore-module
description: Execute nf-core modules from the local project directory. Use when testing, running, or validating nf-core bioinformatics modules on sample data.
allowed-tools: Bash, Read, Glob, mcp__seqera__search_nfcore_module, mcp__seqera__describe_nfcore_module
---

# Run nf-core Modules

Execute nf-core modules that are installed locally in the project.

## ⛔ NEVER WRITE WRAPPER WORKFLOWS

**If a module fails due to missing arguments or incorrect parameters:**

❌ **WRONG** - Writing a wrapper workflow:
```groovy
// NEVER DO THIS - even if the module fails!
include { FASTQC } from './modules/nf-core/fastqc/main'
workflow { FASTQC(Channel.fromPath('*.fq.gz')) }
```

✅ **CORRECT** - Use Seqera MCP to get the correct parameters:
```
mcp__seqera__describe_nfcore_module(module_name="nf-core/fastqc")
```

**When a module run fails:**
1. Call `mcp__seqera__describe_nfcore_module` to get correct input/parameter schema
2. Fix the command-line arguments based on the schema
3. Re-run directly with `nextflow run modules/nf-core/<module>/main.nf ...`

**NEVER create a wrapper workflow as a "fix" for missing arguments.**

## Step 1: Call Seqera MCP FIRST (MANDATORY)

**Before running ANY module, you MUST call `mcp__seqera__describe_nfcore_module` first.**

```
mcp__seqera__describe_nfcore_module(module_name="nf-core/<module>")
```

This returns:
- **`READY_TO_RUN_COMMAND.nextflow_command`** - The exact command template to use
- **Input schemas** - Required files and their formats
- **Parameters** - Available options with descriptions

### Workflow: Get Template → Substitute Values → Run

1. **Call MCP** to get the command template:
   ```
   mcp__seqera__describe_nfcore_module(module_name="nf-core/fastqc")
   ```

2. **Extract** the `READY_TO_RUN_COMMAND.nextflow_command` from the response

3. **Substitute** placeholder values with actual file paths from the user's data

4. **Run** the customized command

### Example

```
# 1. Call MCP first
mcp__seqera__describe_nfcore_module(module_name="nf-core/fastqc")

# 2. MCP returns template like:
#    nextflow run modules/nf-core/fastqc/main.nf --input <FASTQ_FILE> --outdir results

# 3. Substitute with actual values:
nextflow run modules/nf-core/fastqc/main.nf \
  --input "/path/to/sample.fq.gz" \
  --outdir results \
  -ansi-log false
```

### Finding Modules
Use `mcp__seqera__search_nfcore_module` with natural language:
- "quality control for FASTQ files"
- "BAM file statistics"
- "sequence alignment"
- "variant calling"

## Step 2: Pre-flight Check

After discovering the module via Seqera MCP, verify it's installed locally:

```bash
# Check if module exists
ls modules/nf-core/<MODULE_NAME>/main.nf
```

**If the module is NOT installed**, use the `install-nfcore-module` skill first:
```bash
nf-core modules install <MODULE_NAME>
```

## Standard Execution Pattern

```bash
nextflow run modules/nf-core/<MODULE_NAME>/main.nf \
  --input "<file1>,<file2>" \
  --outdir results \
  -ansi-log false \
  -resume
```

## Examples

### Single-end FASTQ
```bash
# Verify module is installed
ls modules/nf-core/fastqc/main.nf

# Run the module
nextflow run modules/nf-core/fastqc/main.nf \
  --input "data/sample.fq.gz" \
  --outdir results_fastqc \
  -ansi-log false
```

### Paired-end FASTQ
```bash
# Verify module is installed
ls modules/nf-core/bwa/mem/main.nf

# Run the module
nextflow run modules/nf-core/bwa/mem/main.nf \
  --input "data/reads_1.fq.gz,data/reads_2.fq.gz" \
  --reference "data/genome.fa" \
  --outdir results_bwa \
  -ansi-log false
```

### With Additional Parameters
```bash
nextflow run modules/nf-core/fastp/main.nf \
  --input "data/R1.fq,data/R2.fq" \
  --skip_trimming \
  --outdir results_fastp \
  -ansi-log false \
  -resume
```

## Complete Workflow: Discover, Check, Install, Run

1. **Discover** module using Seqera MCP:
   ```
   mcp__seqera__search_nfcore_module(query="quality control for FASTQ")
   mcp__seqera__describe_nfcore_module(module_name="nf-core/fastqc")
   ```

2. **Check** if module is installed locally:
   ```bash
   ls modules/nf-core/fastqc/main.nf
   ```

3. **Install** if missing (use `install-nfcore-module` skill):
   ```bash
   nf-core modules install fastqc
   ```

4. **Run** the module using info from `describe_nfcore_module`:
   ```bash
   nextflow run modules/nf-core/fastqc/main.nf \
     --input "data/sample.fq.gz" \
     --outdir results \
     -ansi-log false
   ```

## Critical Rules

1. **CALL MCP FIRST** - Always call `mcp__seqera__describe_nfcore_module` BEFORE attempting to run any module
2. **USE THE COMMAND TEMPLATE** - Extract `READY_TO_RUN_COMMAND.nextflow_command` and substitute actual values
3. **NEVER write wrapper workflows** - if a run fails, call MCP again to get correct args
4. **NEVER guess parameters** - always get them from MCP response
5. **Check module exists locally** - verify `modules/nf-core/<MODULE>/main.nf` exists
6. **Install if missing** - use `nf-core modules install <MODULE>`
7. **Always use `-ansi-log false`** - prevents log formatting issues
8. **Expand wildcards first** - use `ls data/*.fq` then comma-separate results
9. **Quote multi-file inputs** - `--input "file1,file2,file3"`
10. **Use absolute paths** when possible
11. **Add `-resume`** to reuse cached results

## When Module Run Fails

**DO NOT write a wrapper workflow.** Instead:

1. Call `mcp__seqera__describe_nfcore_module(module_name="nf-core/<module>")`
2. Read the input schema and required parameters from the response
3. Fix your `nextflow run` command with correct arguments
4. Re-run the corrected command

## Finding Output Files

Task outputs are in the work directory. Find the task ID in stdout:
```
[ab/123456] process > MODULE_NAME (sample) [100%] 1 of 1
```

Then check:
```bash
ls work/ab/123456*/
```
