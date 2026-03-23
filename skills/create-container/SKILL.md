---
name: create-container
description: Provision containers on-the-fly for conda software packages using Seqera Wave. Use when you need a container to run a bioinformatics tool provided by a conda package.
allowed-tools: mcp__seqera__search_seqera_api, mcp__seqera__call_seqera_api
---

# Container Provisioner

Provision containers on-demand for conda software packages using Seqera Wave service via MCP.

## When to Use This Skill

- Need to run a tool that requires a specific conda package
- Want a container without building it manually
- Need reproducible containerized environments
- Running bioinformatics tools from bioconda

## 2-Step Process

### Step 1: Find the Conda Package

Search for the package to get exact name and version:

```
call_seqera_api(
  service: "seqerahub",
  api_name: "seqerahub_search_conda",
  parameters: {
    "query": "<tool_name>",
    "sources": ["conda"],
    "channels": ["bioconda", "conda-forge"],
    "limit": 5
  }
)
```

### Step 2: Provision the Container

Create the container with Wave:

```
call_seqera_api(
  service: "wave",
  api_name: "wave_claim_container",
  parameters: {
    "format": "docker",
    "packages": {
      "type": "conda",
      "entries": ["<package>=<version>"],
      "channels": ["bioconda", "conda-forge"]
    }
  }
)
```

## Live Example: Provisioning BWA Container

### Step 1: Search for bwa package

```
seqerahub_search_conda(query: "bwa", sources: ["conda"], channels: ["bioconda"], limit: 3)
```

**Result:**
```json
{
  "name": "bwa",
  "channel": "bioconda",
  "latest_version": "0.7.19",
  "versions": ["0.7.19", "0.7.18", "0.7.17", ...]
}
```

### Step 2: Provision container with bwa

```
wave_claim_container(
  format: "docker",
  packages: {
    type: "conda",
    entries: ["bwa=0.7.19"],
    channels: ["bioconda", "conda-forge"]
  }
)
```

**Result:**
```
Container Image: wave.seqera.io/wt/1dc0b2c8e791/wave/build:bwa-0.7.19--6405a90d54563071

Pull command:
docker pull wave.seqera.io/wt/1dc0b2c8e791/wave/build:bwa-0.7.19--6405a90d54563071
```

## Multiple Packages

Combine multiple tools in one container:

```
wave_claim_container(
  format: "docker",
  packages: {
    type: "conda",
    entries: ["samtools=1.17", "bwa=0.7.19", "picard=3.0.0"],
    channels: ["bioconda", "conda-forge"]
  }
)
```

## Common Bioinformatics Packages

| Tool | Package | Channel |
|------|---------|---------|
| BWA | `bwa` | bioconda |
| Samtools | `samtools` | bioconda |
| FastQC | `fastqc` | bioconda |
| MultiQC | `multiqc` | bioconda |
| BCFtools | `bcftools` | bioconda |
| GATK4 | `gatk4` | bioconda |
| STAR | `star` | bioconda |
| Salmon | `salmon` | bioconda |
| Minimap2 | `minimap2` | bioconda |
| Bowtie2 | `bowtie2` | bioconda |

## Using the Container

### With Docker directly
```bash
docker run -v $(pwd):/data wave.seqera.io/wt/<token>/wave/build:<tag> bwa mem ...
```

### In Nextflow config
```groovy
process {
    container = 'wave.seqera.io/wt/<token>/wave/build:<tag>'
}

docker.enabled = true
```

### With Wave auto-provisioning (recommended for Nextflow)
```groovy
wave.enabled = true
wave.strategy = 'conda,container'
docker.enabled = true
```

## Container Formats

| Format | Use Case |
|--------|----------|
| `docker` | Standard Docker environments |
| `sif` | Singularity/Apptainer (HPC clusters) |

## Durable Containers with `freeze`

By default, Wave provides **ephemeral containers** with temporary names that expire after a few hours. For production workflows requiring **reproducible, permanent container names**, use the `freeze` option.

### Ephemeral vs Frozen Containers

| Type | Container Name | Lifespan | Use Case |
|------|----------------|----------|----------|
| **Ephemeral** (default) | `wave.seqera.io/wt/<token>/...` | Few hours | Development, testing |
| **Frozen** | `community.wave.seqera.io/...` | Permanent | Production, reproducibility |

### Provisioning a Frozen Container

```
wave_claim_container(
  format: "docker",
  packages: {
    type: "conda",
    entries: ["bwa=0.7.19"],
    channels: ["bioconda", "conda-forge"]
  },
  freeze: true
)
```

**Result:**
```
Container Image: community.wave.seqera.io/library/bwa:0.7.19--6405a90d54563071
```

### Benefits of Frozen Containers

- **Reproducible names**: Same package spec always produces same container name
- **Permanent storage**: Stored in Wave community registry, never expires
- **Production-ready**: Suitable for published workflows and pipelines
- **Auditable**: Container name includes package versions and build hash

## Notes

- Containers are cached and reused for identical package specs
- Ephemeral containers expire after a few hours
- Use `freeze: true` for permanent, reproducible containers (conda packages)
- ARM64 supported for compatible packages
