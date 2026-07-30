# Topic Channels Migration

A **topic channel** is a channel that any process can send outputs to, and that any part of the pipeline can consume with `channel.topic(name)` — no wiring in between. The main use case is **tool versions**: instead of threading a `ch_versions` channel through every workflow and mixing in `X.out.versions` after every call, each process sends its tool versions to a `versions` topic and the entry workflow reads them via `channel.topic('versions')`.

## The migration loop

### Step 1: Detect

Find the versions plumbing:

```bash
grep -rn "emit: versions\|ch_versions\|out.versions" --include='*.nf' .
```

Record, for each hit, whether it is:

- a **process output** (`path "versions.yml", emit: versions`) — becomes a topic emission
- **plumbing** (`ch_versions = channel.empty()`, `ch_versions.mix(...)`, `versions` in a workflow `take:`/`emit:` section, `ch_versions` passed as a call argument) — gets deleted
- a **consumer** (usually `softwareVersionsToYAML(ch_versions)` in the entry workflow) — switches to `channel.topic('versions')`

### Step 2: Fix

1. **Send process outputs to the topic** — replace `emit:` with `topic:` in each process's `output:` section:

   ```nextflow
   // before
   path "versions.yml", emit: versions

   // after
   path "versions.yml", topic: versions
   ```

2. **Consume the topic** where the versions channel was consumed:

   ```nextflow
   // before
   ch_collated_versions = softwareVersionsToYAML(ch_versions)

   // after
   ch_collated_versions = softwareVersionsToYAML(channel.topic('versions'))
   ```

3. **Delete the plumbing** — every `ch_versions` declaration, every `.mix(X.out.versions)`, every `versions` entry in a `take:`/`emit:` section, and the corresponding argument at each call site:

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

Run `nextflow lint -o concise .` — the deleted `take:`/`emit:` entries must be gone from every call site, and lint catches the mismatches.

Then run the pipeline and compare the collated versions file (e.g. `pipeline_info/*_versions.yml`) against a pre-migration run. It should list the same tools; ordering may differ unless the consumer sorts.

```bash
nextflow run . -profile test,docker --outdir results -resume
```

## Gotchas

- **A process that consumes a topic must not send anything to it — the pipeline will hang forever.** For example, `MULTIQC` typically takes the collated versions file as input, so its own version output must stay a regular `emit:` (or be dropped), not `topic: versions`.
- **Topic order is nondeterministic.** Values arrive as tasks complete. If the output must be stable, sort or `unique()` in the consumer — nf-core's `softwareVersionsToYAML` already does.
- **`emit:` and `topic:` can coexist** on the same output. Keep the `emit:` only if something still consumes `.out.versions` directly.
- **Only convert processes whose versions actually reach the consumer.** If a process's versions were deliberately never mixed in, sending them to the topic changes behavior.

## Critical rules for this migration

1. **NEVER SEND THE CONSUMER'S OWN VERSIONS TO THE TOPIC** — any process that consumes `channel.topic('versions')` output (directly or indirectly) must not emit to that topic, or the pipeline deadlocks.
2. **DELETE ALL THE PLUMBING** — a half-migrated pipeline that still threads `ch_versions` around while also using the topic will double-report versions.
