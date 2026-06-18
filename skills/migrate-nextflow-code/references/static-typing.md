# Static Typing Migration

Nextflow 26.04 introduces **static typing**: type annotations on params, workflow inputs/outputs, and process inputs/outputs, plus **records** (named data structures that replace tuples). The goal of this migration is to add types and convert tuples to records **without changing pipeline behavior**, so the type checker can catch type errors before runtime.

Typing is **opt-in and backward-compatible** — you enable it per file with a feature flag, so the migration can proceed one script at a time.

Reference:
- https://docs.seqera.io/nextflow/process-typed
- https://docs.seqera.io/nextflow/workflow-typed
- https://docs.seqera.io/nextflow/reference/stdlib-types
- https://docs.seqera.io/nextflow/tutorials/static-types
- https://docs.seqera.io/nextflow/tutorials/static-types-operators

## Before you start

1. **Strict syntax must be clean first.** Typed code requires the strict (v2) syntax parser. If `nextflow lint -o concise .` reports any errors, do the [strict syntax migration](strict-syntax.md) before this one. Typing builds on top of it.
2. **This is a large, invasive migration — not a parser fix.** Converting tuples to records reshapes channels, inputs, outputs, and the operators between them. Do it **incrementally**, one file at a time, enabling the flag per file and re-running the type checker, rather than flipping everything at once.
3. **Records are the point.** The payoff is replacing `tuple val(meta), path(...)` with records whose fields have names and types (`sample.id`, `sample.bam`).

## Enabling types

Typed processes and workflows require **both**:

- Nextflow 26.04 or newer
- A feature flag at the top of each script that uses static typing:

  ```nextflow
  nextflow.enable.types = true
  ```

## The loop: detect → fix → verify

### Step 1: Detect

**`nextflow lint` does *not* type-check** — it only checks syntax. Static type checking lives in the Nextflow language server (the engine behind the VS Code extension). This skill bundles a wrapper that drives that language server headlessly and prints its diagnostics:

```bash
python3 <skill-dir>/scripts/nf-typecheck.py <project-dir>
```

- On first run it downloads the 26.04 language server jar to `~/.nextflow/lsp/v26.04/` (needs Java 17+ and network access); later runs reuse it.
- It prints one line per diagnostic, grouped by file: `path:line:col: severity: message`, followed by a summary. Add `--json` for machine-readable output, or `--paranoid` to surface every warning.
- **Type mismatches are reported at `warning` severity** (e.g. `The + operator is not defined for operands with types String and Integer`), alongside genuine `error`s. Don't rely on the exit code alone — read the `warning` lines, since the type errors you are chasing live there.

Work **outward from the leaves**: type the process modules first, then the subworkflows that call them, then the entry workflow and params. A typed process forces its callers to provide correctly-shaped records, so the errors guide you up the call tree.

### Step 2: Fix

For each file, top to bottom:

1. Add `nextflow.enable.types = true`.
2. Convert process/workflow inputs and outputs using the [tables below](#reference-untyped--typed).
3. Replace tuples with records; define shared record types once (see [Record types](#record-types)).
4. Swap legacy operators that don't work under typing (see [Operators](#operators-under-typing)).
5. Apply the **smallest behavior-preserving change** — same files staged, same values emitted. This is not a logic refactor.

### Step 3: Verify

Re-run `python3 <skill-dir>/scripts/nf-typecheck.py <project-dir>` after each file and repeat until it reports **`No diagnostics. ✓`** for the files you are migrating.

Then confirm behavior is unchanged with the project's tests:

```bash
nf-test test          # if the pipeline uses nf-test
nextflow run . -profile test,docker --outdir results   # otherwise, a test profile run
```

The published output tree and emitted values must match a pre-migration run.

## Reference: untyped → typed

### Process inputs

The `input:` section becomes a list of `name: Type` declarations — no `tuple`/`val`/`path` qualifiers.

| Untyped | ✅ Typed |
|---------|---------|
| `val meta` | `meta: Map` (or `meta: Record`) |
| `path reads` | `reads: Path` |
| `path "*.fq"` (collection) | `reads: List<Path>` (ordered) / `Bag<Path>` (unordered) / `Set<Path>` |
| `val x` that may be absent | `x: String?` (nullable via `?`) |
| `tuple val(meta), path(reads)` | one record: `record(meta: Record, reads: List<Path>)`, or a named type `sample: Sample` |
| two separate channel inputs | two declarations, each on its own line — no `tuple` wrapper |

The `path` qualifier becomes the `Path` **type**; `val` qualifiers drop entirely and you name the concrete type (`String`, `Integer`, `Float`, `Boolean`, `Map`, `List<T>`, …). `Channel` and `Value` are **not** valid input types — those are workflow-level only.

### Process input staging

Staging options that lived on the input qualifier move to a dedicated `stage:` section:

| Untyped | ✅ Typed |
|---------|---------|
| `path(fasta, stageAs: 'tmp/*')` | input `fasta: Path` + `stage: stageAs fasta, 'tmp/*'` |
| `env 'FOO'` | input `foo: String` + `stage: env 'FOO', foo` |
| `stdin` | input `message: String` + `stage: stdin message` |

### Process outputs

The `output:` section declares results as optional `name: Type = expression`. Use `file()` / `files()` instead of the `path` qualifier.

| Untyped | ✅ Typed |
|---------|---------|
| `path "out.txt"` | `out: Path = file('out.txt')` (or just `file('out.txt')` for a single unnamed output) |
| `path "*.bam"` (collection) | `files('*.bam')` |
| `path "*.log", optional: true` | `file('*.log', optional: true)` |
| `stdout` | `stdout()` |
| `env FOO` | `env('FOO')` |
| `tuple val(meta), path("*.bam"), emit: bam` | a record: `record(meta: meta, bam: file("*.bam"))` |

A typed process typically emits a single **fat record** carrying everything downstream needs (the `meta` map, each named file) instead of many skinny tuples. Records are duck-typed, so extra fields are fine.

### Versions and the `topic:` section

The `path "versions.yml", topic: versions` idiom is replaced by a **topic emission**:

```nextflow
topic:
file("versions.yml") >> 'versions'
```

Collect them in the entry workflow with `channel.topic('versions')` instead of threading a `ch_versions` channel through every call. This also lets you delete the `ch_versions = ch_versions.mix(...)` plumbing.

### The `when:` block

Typed processes drop the `when: task.ext.when == null || task.ext.when` idiom.

### Record types

Define reusable record types once and `include` them where needed, rather than redeclaring inline everywhere:

```nextflow
// utils/types.nf
record Sample {
    id: String
    meta: Record
    reads: List<Path>
}
```

```nextflow
include { Sample } from '../../utils/types.nf'
```

Records are **duck-typed**: a value satisfies a record type if it has at least the declared fields. Use `record(field: value, ...)` to construct one and `r + record(extra: v)` to add fields. Access fields by name (`sample.id`).

### Workflow inputs and outputs

`take:` and `emit:` gain type annotations. Channels use `Channel<T>`; dataflow values use `Value<T>`; regular values just use `T`.

Inputs (`take:`)

| Untyped | ✅ Typed |
|---------|---------|
| `ch_samples` | `ch_samples: Channel<Sample>` |
| input file (from params) | `fasta: Path` |
| input file (from upstream process) | `val_fasta: Value<Path>` |
| optional input | `val_index: Value<Path>?` or `index: Path?` |

Outputs (`emit:`)

| Untyped | ✅ Typed |
|---------|---------|
| per-sample channel output | `results: Channel<MethylseqResult> = ch_results` |
| optional single-value output | `multiqc_report: Value<Path>? = val_report` |

Inside the body, build a result channel by `join`-ing the per-step record channels on a shared field (e.g. `by: 'id'`) so each sample's outputs collapse into one fat record that matches the emitted record type.

### Typed params

Replace scattered `params.x = ...` assignments with a typed `params {}` block. No default = **required** (the run fails if omitted); `?` marks optional; a Boolean with no default defaults to `false`.

```nextflow
params {
    input: String                              // required
    outdir: Path = 'results'                    // default
    fasta: Path?                                // optional
    aligner: String = 'bismark'
    save_reference: Boolean                     // defaults to false
    clip_r1: Integer = 0
}
```

## Operators under typing

Typed channels carry records, and several legacy operators should be avoided. The full matrix is in the [operators tutorial](https://docs.seqera.io/nextflow/tutorials/static-types-operators); the common swaps:

| Avoid / changed | ✅ Use under typing |
|-----------------|--------------------|
| `Channel.of(...)` (capitalized factory) | `channel.of(...)` |
| `.set { x }` / `.tap { x }` | plain assignment: `x = ch` |
| `PROCESS.out.foo` | assign the call result: `out = PROCESS(...)`, then `out.foo` |
| `a \| b`, `a & b` (pipe/fork) | explicit intermediate assignments |
| `.branch { ... }` | one `.filter { r -> ... }` per branch |
| `.multiMap { ... }` | pass records directly, or one `.map { }` per output |
| `.groupTuple()` | `.groupBy()` with 2-tuples `(key, value)` or 3-tuples `(key, size, value)` |
| `.join(other)` | `.join(other, by: 'id')` — `by` is required |
| `.splitCsv()` (as an operator) | `.flatMap { f -> f.splitCsv() }` |
| `.mix(a, b, c)` | chain: `.mix(a).mix(b).mix(c)` |
| `.collectFile(...)` | workflow outputs, or `collect` + a small write process |
| `each` input qualifier | `.combine(...)` in the caller |
| implicit closure param `it` | name it: `{ r -> ... }` |

## Critical rules for this migration

1. **STRICT SYNTAX FIRST** — Typed code requires the v2 parser. Run `nextflow lint -o concise .` and resolve all strict-syntax errors (see [strict-syntax.md](strict-syntax.md)) before adding any types.
2. **MIGRATE INCREMENTALLY** — Enable `nextflow.enable.types = true` per file, type the leaf modules first, then work up through subworkflows to the entry workflow. Re-run the type checker after each file.
3. **PREFER RECORDS OVER TUPLES** — Convert `tuple val(meta), path(...)` to records with named, typed fields. Define shared record types once and `include` them. Access fields by name, never by index.
4. **PRESERVE BEHAVIOR** — Same files staged, same values emitted, same conditions.
5. **SWAP LEGACY OPERATORS** — Replace `set`/`tap`, `.out`, `|`/`&`, `branch`, `multiMap`, operator-form `splitCsv`, and capitalized `Channel.` factories per the operators table.
6. **VERIFY** — Re-run `scripts/nf-typecheck.py` until it reports `No diagnostics. ✓` (type mismatches surface as `warning`s — read them, don't trust the exit code alone), then run the project's tests to confirm the output tree and emitted values are unchanged.
