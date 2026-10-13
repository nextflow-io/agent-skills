# Static Typing: Workflows

Part of the [static typing migration](static-typing.md). This page covers typing a **workflow**: its `take:`/`emit:` interface and the channel operators in its body.

## Workflow inputs and outputs

`take:` and `emit:` gain type annotations. Channels use `Channel<V>`; dataflow values use `Value<V>`; regular values just use `V`.

Inputs (`take:`)

| Untyped | ✅ Typed |
|---------|----------|
| `ch_samples` | `ch_samples: Channel<Sample>` |
| input file (from params) | `fasta: Path` |
| input file (from upstream process) | `val_fasta: Value<Path>` |
| optional input | `val_index: Value<Path?>` or `index: Path?` |

Outputs (`emit:`)

| Untyped | ✅ Typed |
|---------|----------|
| per-sample channel output | `results: Channel<MethylseqResult> = ch_results` |
| optional singleton output | `multiqc_report: Value<Path?> = val_report` |

Inside the body, join the per-sample result channels into one fat record channel with a single unified record type (see below).

## Record types

Record types can be defined and included across scripts. In practice, record types are only needed to define workflow input/output types:

```nextflow
workflow ALIGN {
    take:
    samples: Channel<Sample>

    // ...

    emit:
    aligned: Channel<AlignedSample>
}

record Sample {
    meta: Map
    reads: List<Path>
}

record AlignedSample {
    meta: Map
    bam: Path
    bai: Path
}
```

Use `record(field: value, ...)` to construct a record and `r + record(extra: v)` to add fields. Access fields by name (`sample.id`).

Records are **duck-typed**: a value satisfies a record type if it has at least the declared fields. The type checker will tell you if a call site has a record mismatch.

## Dataflow logic

Migrating dataflow logic to static typing consists of:

1. removing legacy syntax patterns (`set`/`tap`, `.out`, `|`/`&`)
2. replacing tuples with records in channels
3. replacing legacy operators with equivalent typed operators

The typed operators are `collect, combine, filter, flatMap, groupBy, join, map, mix, reduce, subscribe, unique, until, view`; all other operators are discouraged under static typing. The full guidelines are in the [operators tutorial](https://docs.seqera.io/nextflow/tutorials/static-types-operators).

### Trivial renames

| Avoid / changed | ✅ Use under typing |
|-----------------|---------------------|
| `Channel.of(...)` (capitalized) | `channel.of(...)` (lowercase) |
| `.set { x }` / `.tap { x }` | plain assignment: `x = ch` |
| `.join(other)` | `.join(other, by: 'id')` — `by` is required |
| `.mix(a, b, c)` | chain: `.mix(a).mix(b).mix(c)` |
| `.distinct()` | `.unique()` |
| implicit closure param `it` | explicit param: `{ r -> ... }` |
| `.collectFile(...)` | deferred — see [acceptable residual warnings](static-typing.md#acceptable-residual-warnings) |

### `.out` access — single vs. multi-output

```nextflow
// ❌ .out on the call name
FOO(ch)
FOO.out.bam

// ✅ multi-output: assign the call result, then access by name
out = FOO(ch)
out.bam
out.bai

// ✅ single output: the call IS the channel — no .out, no field access
bam = FOO(ch)   // bam is the output channel directly
```

**Calling an untyped workflow:** the type checker can't infer an untyped workflow's emit shape, so named-emit access (`init.ids`) compiles clean but fails at runtime if the callee is single-emit (it returns the channel directly — use `init` alone).

### Pipe / fork (`|`, `&`)

```nextflow
// ❌ pipe and fork
ch | FOO | BAR
FOO & BAR

// ✅ explicit calls
BAR(FOO(ch))
FOO(ch) ; BAR(ch)
```

### `.branch { }` → one `.filter` per branch

```nextflow
// ❌ branch
ch.branch { r ->
    aspera: r.method == 'aspera'
    ftp:    r.method == 'ftp'
}

// ✅ one filter per branch (add a .map if you were reshaping in the branch)
ch.filter { r -> r.method == 'aspera' }
ch.filter { r -> r.method == 'ftp' }
```

### `.multiMap { }` → pass records directly, or one `.map` per output

```nextflow
// ❌ multiMap
ch.multiMap { r ->
    reads: r.reads
    meta:  r.meta
}

// ✅ one map per output (or just pass the record through and access fields downstream)
ch.map { r -> r.reads }
ch.map { r -> r.meta }
```

### `.groupTuple()` → `.groupBy()`

`groupBy` takes **no closure** — it takes a channel of `(key, value)` tuples, groups them by key, and emits `(key, values)` tuples. To fix the expected group size (as `groupTuple`'s `size:` did), feed `(key, size, value)` tuples instead.

```nextflow
// ❌ groupTuple
ch.groupTuple()          // or groupTuple(by: 0)

// ✅ groupBy on a channel of (key, value) tuples, then destructure
ch.groupBy()             // emits (key, values) tuples — no closure argument
  .map { key, values -> record(id: key, files: values) }
```

### `.splitCsv()` operator → `.flatMap`

```nextflow
// ❌ splitCsv as a channel operator
ch.splitCsv(header: true)

// ✅ flatMap + the per-file splitCsv method
ch.flatMap { f -> f.splitCsv(header: true) }
```

`splitCsv` returns `List<?>` — the row type is ambiguous, so the type checker rejects field/element access until you cast each row:

- **with `header: true`** → cast each row to `Map<String,String>` (access by column name)
- **without a header** → cast each row to `List<String>` (access by position)

```nextflow
ch.flatMap { f -> f.splitCsv(header: true) }
  .map { row -> row as Map<String,String> }
```

### `each` input qualifier → `.combine` in the caller

```nextflow
// ❌ each qualifier fans the process out over a list
process ALIGN {
    input:
    path(reads)
    each aligner
}
ALIGN(ch_reads, ['bwa', 'bowtie2'])

// ✅ drop `each`; expand the combinations with combine() in the caller
process ALIGN {
    input:
    tuple(reads: Path, aligner: String)
}
aligners = channel.of('bwa', 'bowtie2')
ALIGN(ch_reads.combine(aligners))
```

## Tips & tricks

Here are some common patterns to use while navigating the type checker.

### Multiple channel inputs

Processes cannot be called with multiple channel inputs. Combine multiple inputs into a single source with `combine` instead.

When the inputs consist of a per-sample record channel and one or more dataflow values, you can use `combine` with named args to append the value to each sample record:

```nextflow
samples = channel.of( record(id: 1, fastq: file('1.fq')) )
index = channel.value( file('index.fa') )
ALIGN( samples.combine(strandedness: 'auto', index: index) )
```

You would also update `ALIGN` to declare a single combined record input.

### Conditional process outputs

A common pattern is to assign a channel to a process output, or an empty channel if the process is skipped:

```nextflow
ch_fastqc = channel.empty()

if (!params.skip_fastqc) {
    ch_fastqc = FASTQC(...)
}
```

The type checker will complain about this because `ch_fastqc` will be typed as `Channel<?>` and any downstream operation (e.g. `ch_fastqc.map { r -> ... }`) will not be able to see the actual record fields from `FASTQC`. Assign the empty channel in an `else` instead:

```nextflow
if (!params.skip_fastqc) {
    ch_fastqc = FASTQC(...)
}
else {
    ch_fastqc = channel.empty()
}
```

### Skinny tuples vs fat records

A common workflow pattern is to call several processes on a single input channel and emit each result separately:

```nextflow
workflow BAM_STATS_SAMTOOLS {
    take:
    ch_samples // channel: [ val(meta), path(fastq) ]

    main:
    FOO(ch_samples)
    BAR(ch_samples)
    BAZ(ch_samples)

    emit:
    foo = FOO.out // channel: [ val(meta), path(foo) ]
    bar = BAR.out // channel: [ val(meta), path(bar) ]
    baz = BAZ.out // channel: [ val(meta), path(baz) ]
}
```

These channels are called **skinny tuples** because they contain thin vertical slices of related per-sample results.

With records it is better to join these channels into a single **fat record** channel:

```nextflow
workflow BAM_STATS_SAMTOOLS {
    take:
    ch_samples: Channel<Sample>

    main:
    ch_foo = FOO(ch_samples)
    ch_bar = BAR(ch_samples)
    ch_baz = BAZ(ch_samples)

    ch_results = ch_foo
        .join(ch_bar, by: 'meta')
        .join(ch_baz, by: 'meta')

    emit:
    ch_results as Channel<FooBarBaz>
}

record Sample {
    meta: Map
    fastq: Path
}

record FooBarBaz {
    meta: Map
    foo: Path
    bar: Path
    baz: Path
}
```
