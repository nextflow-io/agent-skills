# Workflow Outputs Migration

Nextflow's **workflow output definition** replaces the legacy `publishDir` directive. Instead of each process deciding where its files land, the entry workflow publishes *channels* through a `publish:` section, and a top-level `output {}` block declares where each published channel's files go. The goal of this migration is to move every `publishDir` into a single `output {}` block **without changing which files are published or where they end up**.

Stable since Nextflow 25.10; this skill assumes **26.04 or later**. Do not use the old `nextflow.preview.output` feature flag — it is no longer needed.

Reference:
- https://docs.seqera.io/nextflow/workflow#outputs
- https://docs.seqera.io/nextflow/tutorials/workflow-outputs

## Before you start: records vs. tuples

Workflow outputs work best with **records** — channel values that are maps with named fields (`sample.fastq_1`, `sample.id`). While workflow outputs can be used with tuples (e.g. `tuple val(meta), path(reads)`), they are far cleaner when the published channel carries records.

**If the pipeline is large and still uses tuples (the `tuple val(meta), path(...)` idiom), STOP.** Tell the user to migrate from tuples to records first, then return to this migration. Workflow outputs are much easier to express once values have named fields, and migrating to it without records on a big pipeline produces a sprawling diff with many workflow emits.

- **Small pipeline (a handful of published outputs):** proceed with the migration — add a `.map { meta, file -> meta + [field: file] }` to transform the final channel when it is published.
- **Large pipeline still on tuples:** stop and recommend the tuples → records migration first.

If the channels already carry records, proceed.

## The loop: detect → fix → verify

### Step 1: Detect

There is no linter for this migration — inventory the existing publishing first. Find every `publishDir` declaration, in both process scripts and config:

```bash
grep -rn "publishDir" --include=*.nf --include=*.config .
```

For each match, record three things: **what** files it publishes (the process output / `pattern:`), **where** they go (the path, including any `saveAs:` closure), and **under what condition** (`enabled:`, surrounding `if`).

### Step 2: Fix

Work top-down, one published output at a time:

1. **Identify the channel** in the entry workflow that carries each set of published files. Outputs produced deep in a subworkflow must be surfaced: add them to the subworkflow's `emit:` block so they propagate up to the entry workflow.
2. **Add a `publish:` section** to the entry `workflow {}`, assigning each output a name: `samples = ch_samples`.
3. **Add a top-level `output {}` block** with a matching entry per name, carrying the `path` / `index` directives as needed (see the table below).
4. **Delete the `publishDir` directives** you replaced.
5. **Set publishing config** once, globally, instead of per-process `mode:`/`outputDir`:

   ```groovy
   outputDir = params.outdir            // keep the existing --outdir CLI flag working
   workflow.output.mode = params.publish_dir_mode
   ```

Apply the **smallest behavior-preserving change** — same files, same destination paths, same conditions. This migration is not a refactor of pipeline logic.

### Step 3: Verify

Run `nextflow lint -o concise .` after the migration to make sure there are no errors.

The pipeline should produce the **exact same output tree** as before. Run the test profile both before and after and compare:

```bash
nextflow run . -profile test,docker --outdir results
```

Compare the published directory structure against a pre-migration run (`diff -r` the two `results/` trees, or compare `find results -type f | sort`). Every file should appear in the same relative location.

## Reference: publishDir → output block

| `publishDir` form | ✅ `output {}` equivalent |
|-------------------|---------------------------|
| `publishDir "${params.outdir}/foo"` | Declare the channel in `publish:`, then `output { x { path 'foo' } }` (the `params.outdir` root moves to `outputDir`) |
| `publishDir mode: 'copy'` (repeated on every process) | Set once: `workflow.output.mode = 'copy'` in config |
| `publishDir "${params.outdir}/foo/${meta.id}"` (path depends on the value) | Dynamic path closure: `path { sample -> "foo/${sample.id}" }` |
| `publishDir saveAs: { fn -> ... }` | Dynamic `path { }` closure, or route individual files with `>>` |
| Multiple `publishDir` with `pattern:` sending files to different dirs | One `path { r -> r.a >> 'dirA/'; r.b >> 'dirB/' }` closure — route each file with `>>` |
| `publishDir enabled: params.save_x` (conditional) | Gate inside the closure: `path { r -> r.file >> (params.save_x ? 'dir/' : null) }` |

Directives available inside an output entry: `path` (static string or closure), `index` (`path`, `header`, `sep`). Config-scope settings (`mode`, `overwrite`, `storageClass`, …) go under `workflow.output.*`.

### The `>>` operator and index files

When one channel value carries several files that go to different places, use the `>>` operator inside the `path` closure. **Only files routed with `>>` are published** in this form:

```nextflow
output {
    samples {
        path { sample ->
            sample.fastq_1 >> 'fastq/'
            sample.fastq_2 >> 'fastq/'
            sample.bam     >> (params.save_bams ? "align/" : null)
        }
        index {
            path 'samplesheet/samplesheet.csv'
            header true
        }
    }
}
```

The `index` directive writes a CSV/JSON/YAML catalog of the channel's values (with metadata preserved) — this is what replaces a hand-rolled "create a samplesheet" process.

## Worked example (rnaseq-nf)

The [workflow outputs tutorial](https://docs.seqera.io/nextflow/tutorials/workflow-outputs) migrates the `rnaseq-nf` pipeline in stages — a good template for the general approach.

**Start:** processes published with `publishDir`. Replace those directives with a `publish:` section in the entry workflow and a matching `output {}` block:

```nextflow
workflow {
    main:
    read_pairs_ch = channel.fromFilePairs(params.reads, checkIfExists: true, flat: true)
    rnaseq = RNASEQ(read_pairs_ch, params.transcriptome)
    multiqc_files = rnaseq.fastqc.mix(rnaseq.quant).collect()
    multiqc_report = MULTIQC(multiqc_files, params.multiqc)

    publish:
    fastqc_logs    = rnaseq.fastqc
    multiqc_report = multiqc_report
}

output {
    fastqc_logs {
    }
    multiqc_report {
    }
}
```

Set the publish mode once in config instead of per-process: `workflow.output.mode = 'copy'`.

**Then refine to records + index file.** The cleanest result joins the per-sample channels into a **record** with named fields, so the output block can route each file by name and emit a samplesheet via `index`:

```nextflow
workflow {
    main:
    // ...
    samples_ch = rnaseq.fastqc
        .join(rnaseq.quant)
        .map { id, fastqc, quant -> [id: id, fastqc: fastqc, quant: quant] }
    multiqc_files = samples_ch.flatMap { s -> [s.fastqc, s.quant] }.collect()
    multiqc_report = MULTIQC(multiqc_files, params.multiqc)

    publish:
    samples        = samples_ch
    multiqc_report = multiqc_report
}

output {
    samples {
        path { sample ->
            sample.fastqc >> "fastqc/${sample.id}"
            sample.quant  >> "quant/${sample.id}"
        }
        index {
            path 'samples.csv'
            header true
        }
    }
    multiqc_report {
    }
}
```

The `index` produces a catalog of the published values:

```csv
"id","fastqc","quant"
"lung","results/fastqc/lung","results/quant/lung"
"gut","results/fastqc/gut","results/quant/gut"
```

Note how the record's named fields (`sample.id`, `sample.fastqc`) make the dynamic `path` closure and the index file straightforward — the payoff of migrating to records first.

## Critical rules for this migration

1. **CHECK RECORDS FIRST** — If the pipeline is large and still uses tuples (`tuple val(meta), path(...)`) rather than records, STOP and recommend migrating tuples → records first. Workflow outputs are much easier with named record fields.
2. **INVENTORY BEFORE EDITING** — `grep` every `publishDir` (scripts and config) and record what/where/condition for each before changing anything. Never guess.
3. **PRESERVE THE OUTPUT TREE** — Same files, same destination paths, same conditions. This is not a refactor of pipeline logic.
4. **publish: AND output {} MUST MATCH** — Every name assigned in `publish:` must be declared in `output {}`, and vice versa.
5. **MATCH THE CLOSURE TO THE CHANNEL** — A dynamic `path { ... }` closure's parameters must match the structure of the published channel's values.
6. **VERIFY BY DIFFING** — Compare the published directory tree before and after; it must be identical. Run the project's tests to confirm.
