---
name: install-nfcore-module
description: Install nf-core modules into the project directory using nf-core tools. Use when adding bioinformatics modules to a local Nextflow pipeline for customization or integration.
allowed-tools: Bash, Read, Glob
---

# Install nf-core Modules

Install nf-core modules locally into your project using the `nf-core` command-line tools.

## Prerequisites

### nf-core tools
Ensure nf-core tools are installed:
```bash
pip install nf-core
# or
conda install -c bioconda nf-core
```

Verify installation:
```bash
nf-core --version
```

### Project Configuration (.nf-core.yml)

**Required for non-interactive installation.** Ensure `.nf-core.yml` exists with `repository_type: pipeline`:

```bash
# Check and create if missing
if [ ! -f .nf-core.yml ]; then
  echo "repository_type: pipeline" > .nf-core.yml
fi
```

Without this file, `nf-core modules install` will prompt interactively asking for the repository type.

### Modules Directory

**Ensure the `modules` directory exists** before installing:

```bash
mkdir -p modules
```

This directory will contain all installed nf-core modules under `modules/nf-core/`.

## Installing Modules

### Pre-Install Check (Skip if Already Installed)

**Before installing, check if the module already exists:**

```bash
# For simple modules (e.g., fastqc)
ls modules/nf-core/<module_name>/main.nf 2>/dev/null && echo "Already installed" || nf-core modules install <module_name> --force

# For nested modules (e.g., samtools/sort)
ls modules/nf-core/<tool>/<subtool>/main.nf 2>/dev/null && echo "Already installed" || nf-core modules install <tool>/<subtool> --force
```

### Non-Interactive Mode (REQUIRED for automation)

**Always use `--force` to avoid interactive prompts:**

```bash
nf-core modules install <module_name> --force
```

| Flag | Purpose |
|------|---------|
| `--force` / `-f` | Force reinstallation, skip confirmation if module exists |
| `--sha` / `-s` | Install module at specific commit SHA |
| `--dir` / `-d` | Specify pipeline directory |

### Examples

```bash
# Install fastqc module (non-interactive)
nf-core modules install fastqc --force

# Install a nested module (tool/subcommand)
nf-core modules install samtools/sort --force
nf-core modules install bwa/mem --force

# Install from a specific nf-core/modules revision
nf-core modules install fastqc --sha <commit_sha> --force
```

### Installation Options

```bash
# Install to a custom directory
nf-core modules install fastqc --dir ./my-pipeline --force

# Install a specific version
nf-core modules install fastqc --sha abc123def --force
```

## Listing Available Modules

```bash
# List all available modules
nf-core modules list remote

# List installed modules in current project
nf-core modules list local

# Search for modules by keyword
nf-core modules list remote | grep -i "align"
```

## Module Information

```bash
# Get info about a specific module
nf-core modules info fastqc

# Show module parameters and inputs
nf-core modules info samtools/sort
```

## Directory Structure

After installation, modules are placed in:
```
modules/
└── nf-core/
    ├── fastqc/
    │   ├── main.nf
    │   ├── meta.yml
    │   └── tests/
    └── samtools/
        └── sort/
            ├── main.nf
            ├── meta.yml
            └── tests/
```

## Using Installed Modules

Include in your workflow:
```groovy
include { FASTQC } from './modules/nf-core/fastqc/main'
include { SAMTOOLS_SORT } from './modules/nf-core/samtools/sort/main'

workflow {
    FASTQC(reads_ch)
    SAMTOOLS_SORT(bam_ch)
}
```

## Updating Modules

```bash
# Check for updates
nf-core modules update --all --preview

# Update a specific module
nf-core modules update fastqc

# Update all modules
nf-core modules update --all
```

## Removing Modules

```bash
nf-core modules remove fastqc
nf-core modules remove samtools/sort
```

## Workflow: Find and Install

1. Ensure project setup:
   ```bash
   [ -f .nf-core.yml ] || echo "repository_type: pipeline" > .nf-core.yml
   mkdir -p modules
   ```

2. Search for module using Seqera MCP:
   ```
   mcp__seqera__search_nfcore_module("read alignment")
   ```

3. Get module details:
   ```
   mcp__seqera__describe_nfcore_module("nf-core/bwa/mem")
   ```

4. Check if installed, install if missing:
   ```bash
   ls modules/nf-core/bwa/mem/main.nf 2>/dev/null && echo "Already installed" || nf-core modules install bwa/mem --force
   ```

5. Include in your pipeline and customize as needed
