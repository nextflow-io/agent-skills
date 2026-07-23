# Static Typing: Workflows

Part of the [static typing migration](static-typing.md). This page covers typing a **workflow**: its `take:`/`emit:` interface and the channel operators in its body.

## Workflow inputs and outputs

`take:` and `emit:` gain type annotations. Channels use `Channel<T>`; dataflow values use `Value<T>`; regular values just use `T`.

Inputs (`take:`)

| Untyped | ✅ Typed |
|---------|----------|
| `ch_samples` | `ch_samples: Channel<Sample>` |
| input file (from params) | `fasta: Path` |
| input file (from upstream process) | `val_fasta: Value<Path>` |
| optional input | `val_index: Value<Path>?` or `index: Path?` |

Outputs (`emit:`)

| Untyped | ✅ Typed |
|---------|----------|
| per-sample channel output | `results: Channel<MethylseqResult> = ch_results` |
| optional singleton output | `multiqc_report: Value<Path>? = val_report` |

Inside the body, build a result channel by `join`-ing the per-step record channels on a shared field (e.g. `by: 'id'`) so each sample's outputs collapse into one fat record that matches the emitted record type.

## Operators under typing

Migrating dataflow logic to static typing consists of:

1. removing legacy syntax patterns (`set`/`tap`, `.out`, `|`/`&`)
2. replacing tuples with records in channels
3. replacing legacy operators with equivalent typed operators

The full guidelines are in the [operators tutorial](https://docs.seqera.io/nextflow/tutorials/static-types-operators).

### Trivial renames

These are direct substitutions:

| Avoid / changed | ✅ Use under typing |
|-----------------|---------------------|
| `Channel.of(...)` (capitalized factory) | `channel.of(...)` — the factory is lowercase |
| `.set { x }` / `.tap { x }` | plain assignment: `x = ch` |
| `.join(other)` | `.join(other, by: 'id')` — `by` is required |
| `.mix(a, b, c)` | chain: `.mix(a).mix(b).mix(c)` |
| implicit closure param `it` | name it: `{ r -> ... }` |
| `.collectFile(...)` | deferred — see [acceptable residual warnings](static-typing.md#acceptable-residual-warnings) |

The structural transformations below need more than a rename.

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

### Pipe / fork (`|`, `&`)

```nextflow
// ❌ pipe and fork
ch | FOO | BAR
FOO & BAR

// ✅ explicit intermediate assignments
foo_out = FOO(ch)
bar_out = BAR(foo_out)
```

### `.branch { }` → one `.filter` per branch

```nextflow
// ❌ branch
ch.branch { r ->
    aspera: r.method == 'aspera'
    ftp:    r.method == 'ftp'
}

// ✅ one filter per branch (add a .map if you were reshaping in the branch)
ch_aspera = ch.filter { r -> r.method == 'aspera' }
ch_ftp    = ch.filter { r -> r.method == 'ftp' }
```

### `.multiMap { }` → pass records directly, or one `.map` per output

```nextflow
// ❌ multiMap
ch.multiMap { r ->
    reads: r.reads
    meta:  r.meta
}

// ✅ one map per output (or just pass the record through and access fields downstream)
reads = ch.map { r -> r.reads }
meta  = ch.map { r -> r.meta }
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
