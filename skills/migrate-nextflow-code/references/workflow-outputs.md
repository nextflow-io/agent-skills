# Workflow Outputs Migration

Nextflow's **workflow output definition** replaces the legacy `publishDir` directive. Instead of each process deciding where to publish files, the entry workflow publishes *channels* through a `publish:` section, and a top-level `output {}` block declares where to publish the files in each channel. The goal of this migration is to move every `publishDir` into a single `output {}` block **without changing which files are published or where they end up**.

Stable since Nextflow 25.10; this skill assumes **26.04 or later**.

Reference:
- https://docs.seqera.io/nextflow/workflow#outputs
- https://docs.seqera.io/nextflow/tutorials/workflow-outputs

## Before you start: skinny tuples vs fat records

Many pipelines model intermediate data as channels of **skinny tuples** — tuples of the form `(meta, file)`, one tuple channel for each output file. For large pipelines, this pattern leads to many intermediate channels. This is problematic for the `output` block because every channel must be propagated to the entry workflow in order to be published. It can be done, but the end result will be extremely verbose, with many more emits than before.

The `output` block works best with channels of **fat records** — a single record channel containing all per-sample output files. Each workflow joins the outputs from different processes and emits one record channel rather than many tuple channels. This pattern makes it *significantly* easier to migrate from `publishDir` to the `output` block.

Before migrating a pipeline to workflow outputs, assess the impact:

- **Any pipeline using fat records:** proceed.

- **Small pipeline using skinny tuples:** proceed.

- **Large pipeline using skinny tuples:** **STOP** and recommend the [tuples → records migration](static-typing.md) first.

## The migration loop

### Step 1: Detect

Inventory the current publishing behavior:

- `publishDir` settings in config
- `publishDir` directives in process definitions
- `collectFile` operators that publish via `storeDir:`

For each match, record the following:

- **Which process** is targeted. Each `publishDir` can target one or more processes based on how it is declared in the config. A catch-all `publishDir` targets all processes that are not captured by a more specific `publishDir` (e.g. a `withName` selector).
- **Which files** are published. By default, `publishDir` publishes all output files declared by the process. It may use the `pattern:` option to publish specific outputs. It may use `enabled:` to toggle the entire declaration based on some condition.
- **Where** files are published. Each `publishDir` specifies a target directory path. It may use a `saveAs:` closure to specify per-file mappings.

### Step 2: Fix

Migrate one published output at a time:

1. **Propagate process outputs** up the call tree (via `emit:`) to the entry workflow so that they can be published.
2. **Add a `publish:` section** to the entry workflow, assigning each output a name: `samples = ch_samples`.
3. **Add a top-level `output {}` block** with a matching entry and `path` directive for each published channel (see the table below).
4. **Delete the `publishDir` directives** you replaced. Delete surrounding config files when they are left empty.

Define global publishing behavior once in config:

```groovy
outputDir = params.outdir // keeps the existing --outdir CLI option working
workflow.output.mode = params.publish_dir_mode
```

Override settings like `mode` in the `output` block as needed:

```nextflow
output {
    samples {
        path '...'
        mode 'symlink'
    }
}
```

Apply the **smallest behavior-preserving change** — same files, same destination paths, same conditions. This migration is not a refactor of pipeline logic.

### Step 3: Verify

Run `nextflow lint -o concise .` after the migration to make sure there are no errors.

The pipeline should produce the **same output tree** as before. Run the test profile both before and after and compare:

```bash
nextflow run . -profile test,docker --outdir results -resume
```

Compare the published directory structure against a pre-migration run. Every file should appear in the same relative location.

Results may differ due to different embedded output paths, timestamps, etc. These differences are acceptable as long as the results are semantically equivalent.

## Reference: publishDir → output block

### Basic publishing

Migrate a basic `publishDir` as follows:

```nextflow
// before
process FOO {
    publishDir "${params.outdir}/foo", mode: 'copy'

    input:
    // ...

    output:
    tuple val(meta), path('...')

    // ...
}

// after
workflow {
    main:
    ch_samples = FOO(/* ... */)

    publish:
    samples = ch_samples
}

output {
    samples {
        // params.outdir root moves to outputDir
        path 'foo'

        // mode moves to workflow.output.mode, override here only if needed
        // mode 'copy'
    }
}
```

You don't need to manually extract or flatten files from a channel — just emit and publish it directly. Nextflow automatically extracts files from data structures (lists, maps, records, tuples).

### Publishing per-sample

When the publish path depends on a per-sample value, use a dynamic `path` closure:

```nextflow
// before
publishDir "${params.outdir}/foo/${meta.id}"

// after
output {
    samples {
        path { sample -> "foo/${sample.id}" }
    }
}
```

### Publishing per-file

When a `publishDir` sends individual files to different places via `pattern:` or `saveAs:`, use the `>>` operator inside the `path` closure:

```nextflow
// before
publishDir '...', pattern: '...'
publishDir '...', saveAs: { fn -> /* ... */ }

// after
output {
    samples {
        path { sample ->
            sample.fastq_1 >> 'fastq/'
            sample.fastq_2 >> 'fastq/'
            sample.bam     >> 'align/'
        }
    }
}
```

Only files routed with `>>` are published when using this form. If the publish target ends with a slash, the source files are published *into* it; otherwise, the source file is published *as* the target name.

### Conditional publishing

When a `publishDir` conditionally publishes files via `enabled:`, use the `enabled` directive or gate inside the `path` closure:

```nextflow
// before
publishDir 'align', enabled: params.save_bams

// after (alt 1)
output {
    samples {
        path 'align'
        enabled params.save_bams
    }
}

// after (alt 2)
output {
    samples {
        path { sample ->
            // ...
            sample.bam >> (params.save_bams ? "align/" : null)
        }
    }
}
```

If a `publishDir` specifies `enabled: false`, it is a no-op — delete it.

### Index files

The `index` directive writes a CSV/JSON/YAML catalog of the channel's values (with metadata preserved):

```nextflow
output {
    samples {
        path { /* ... */ }
        index {
            path 'samplesheet.csv'
            header true
        }
    }
}
```

It can replace a `collectFile` operation or a hand-rolled "create a samplesheet" process. However, such a refactor might not be trivial — flag any opportunities for `index` refactoring as follow-up work.

## Critical rules for this migration

1. **CHECK RECORDS FIRST** — If the pipeline is large and still uses tuples (`tuple val(meta), path(...)`) rather than records, STOP and recommend the [tuples → records migration](static-typing.md) first. Workflow outputs are much easier with fat records.
2. **INVENTORY BEFORE EDITING** — Find every `publishDir` (scripts and config) and record what/where/condition for each before changing anything.
3. **VERIFY BY DIFFING** — Compare the published directory tree before and after; it must be identical. Run the project's tests to confirm.
