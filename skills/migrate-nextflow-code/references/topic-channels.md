# Topic Channels Migration

A **topic channel** is a channel that any process can send outputs to, and that any part of the pipeline can consume with `channel.topic(name)` — no wiring in between. The main use case is **tool versions**: instead of threading a `ch_versions` channel through every workflow and mixing in `X.out.versions` after every call, each process sends its tool versions to a `versions` topic and the entry workflow reads them via `channel.topic('versions')`.

The topic carries a **tuple per tool**, not a file:

```nextflow
tuple val("${task.process}"), val('samtools'), eval("samtools version | sed '1!d;s/.* //'"), topic: versions
```

Each value arriving on the topic is `[ process, tool, version ]`. That shape drives everything below — most importantly, nf-core's `softwareVersionsToYAML` does **not** work on it (see Step 2.2).

## The migration loop

### Step 1: Detect

Find the versions plumbing:

```bash
grep -rn "emit: versions\|topic: versions\|ch_versions\|out.versions" --include='*.nf' .
```

Record, for each hit, which of these it is:

- a **legacy version output** (`path "versions.yml", emit: versions`) — becomes a topic emission
- an **already-migrated version output** (`..., topic: versions`) — leave alone
- **plumbing** (`ch_versions = channel.empty()`, `ch_versions.mix(...)`, `versions` in a workflow `take:`/`emit:` section, `ch_versions` passed as a call argument) — gets deleted
- a **consumer** (usually `softwareVersionsToYAML(ch_versions)` in the entry workflow) — switches to `channel.topic('versions')`

The pipeline may already have some modules on `topic: versions` while the rest still write `versions.yml`. When both schemes coexist there is usually **reconciliation scaffolding** holding them together. That scaffolding exists *only* because the migration is incomplete: it is plumbing, and it gets deleted too.

### Step 2: Fix

1. **Send process outputs to the topic.** Move the version command out of the `script:` heredoc and into an `eval()` in the `output:` section:

   ```nextflow
   // before
   output:
   path "versions.yml", emit: versions

   script:
   """
   ...
   cat <<-END_VERSIONS > versions.yml
   "${task.process}":
       bedtools: \$(bedtools --version | sed -e "s/bedtools v//g")
   END_VERSIONS
   """

   // after
   output:
   tuple val("${task.process}"), val('bedtools'), eval('bedtools --version | sed -e "s/bedtools v//g"'), topic: versions

   script:
   """
   ...
   """
   ```

   Delete the heredoc from `script:` and `stub:` (if present), and each branch of a multi-branch script. One tuple per tool: a process reporting two tools emits two lines.

   **The `eval()` string must not contain `$(...)` or a bare `$`.** Rewrite it:

   ```nextflow
   // breaks — command substitution, and a `$` anchor in the sed expression
   eval('echo $(qualimap 2>&1) | sed "s/^.*QualiMap v.//; s/Built.*$//"')

   // works — pipe directly, drop the `$` anchor
   eval('qualimap 2>&1 | grep -m1 "QualiMap v" | sed "s/^.*QualiMap v.//"')
   ```

   The `echo $(...)` idiom exists in the heredocs to flatten multi-line output onto one line; replace it with `head -1`, `grep -m1`, or `sed -n '...p'`. Use a single-quoted string when the command contains double quotes (and vice versa) so nothing interpolates.

2. **Consume the topic** where the versions channel was consumed:

   ```nextflow
   // before
   softwareVersionsToYAML(ch_versions)
       .collectFile(storeDir: "${params.outdir}/pipeline_info", name: '..._versions.yml', sort: true, newLine: true)

   // after
   channel.topic('versions')
       .unique()
       .map { process, tool, version -> [process.tokenize(':')[-1], "${tool}: ${version}"] }
       .groupTuple()
       .map { process, tools -> "${process}:\n  ${tools.sort().join('\n  ')}" }
       .mix(channel.of(workflowVersionToYAML()))
       .collectFile(storeDir: "${params.outdir}/pipeline_info", name: '..._versions.yml', sort: true, newLine: true)
   ```

3. **Delete the plumbing** — every `ch_versions` declaration, every `.mix(X.out.versions)`, every `versions` entry in a `take:`/`emit:` section, the corresponding argument at each call site, and any reconciliation scaffolding:

   ```nextflow
   // before
   workflow ALIGN {
       take:
       reads
       ch_versions

       main:
       BWAMETH_ALIGN(reads)
       ch_versions = ch_versions.mix(BWAMETH_ALIGN.out.versions)

       emit:
       bam = BWAMETH_ALIGN.out.bam
       versions = ch_versions
   }

   // after
   workflow ALIGN {
       take:
       reads

       main:
       BWAMETH_ALIGN(reads)

       emit:
       bam = BWAMETH_ALIGN.out.bam
   }
   ```

### Step 3: Verify

Run `nextflow lint -o concise .` to check for mismatches. The deleted `take:`/`emit:` entries must be removed from every call site. Search for and remove any dangling `*SUB*.out.versions` references.

Then run the pipeline and compare the collated versions file against a pre-migration run:

```bash
nextflow run . -profile test,docker --outdir results -resume
```

It should list the same tools; ordering may differ, and duplicate lines legitimately disappear if the pre-migration consumer used `.distinct()`. Diff the whole output tree, not just the versions file — the only expected differences are the versions file itself, any `versions.yml` that was being published as a side effect of a `publishDir`, and any separate topic-versions file you deleted.

**nf-test snapshots will need regenerating.** Pipeline-level tests typically snapshot the collated versions file (`removeNextflowVersion("$outputDir/pipeline_info/..._versions.yml")`), and `versions.yml` disappears from published outputs. Expect every snapshot that touches versions to mismatch, and update them once you have confirmed the diff is only what you intended:

```bash
nf-test test --update-snapshot
```

## Gotchas

- **A process that consumes a topic must not send anything to it — the pipeline will hang forever.** For example, `MULTIQC` typically takes the collated versions file as input, so its own version output must stay a regular `emit:` or be dropped, not `topic: versions`.
- **Use `.unique()`, not `.distinct()`.** `distinct()` only collapses *consecutive* duplicates, and topic values from per-sample tasks arrive interleaved — so a process that ran three times appears three times in the output.
- **One tuple per tool means duplicate YAML keys.** A process reporting two tools emits two values, which naively become two `PROCESS:` blocks. `groupTuple()` by process name before formatting.
- **Topic order is nondeterministic.** Values arrive as tasks complete; use `sort: true` on `collectFile` if the output must be stable.
- **`emit:` and `topic:` can coexist** on the same output. Keep the `emit:` only if something still consumes `.out.versions` directly.
- **Only convert processes whose versions actually reach the consumer.** If a process's versions were deliberately never mixed in, sending them to the topic changes behavior.

## Critical rules for this migration

1. **NEVER SEND THE CONSUMER'S OWN VERSIONS TO THE TOPIC** — any process that consumes `channel.topic('versions')` output (directly or indirectly) must not emit to that topic, or the pipeline deadlocks.
2. **NEVER PUT `$(...)` OR A BARE `$` IN AN `eval()`** — Nextflow runs it inside a double-quoted `bash -c`, so the outer shell expands it first and the task fails with exit 127. Pipe directly instead of `echo $(...)`, and drop `$` anchors from sed expressions.
3. **DELETE ALL THE PLUMBING** — a half-migrated pipeline that still threads `ch_versions` around while also using the topic will double-report versions.
