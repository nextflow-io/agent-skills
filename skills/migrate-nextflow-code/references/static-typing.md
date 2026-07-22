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

Static type checking is provided by the Nextflow language server, which is included in this plugin. After you edit a `.nf` or `nextflow.config` file, Claude Code pushes the server's diagnostics into your context automatically.

- The language server jar is downloaded on first use; no action needed from you.
- **Type checking only runs on files that opt in** with `nextflow.enable.types = true`.
- Some type mismatches are reported as errors while others are reported as warnings -- make sure to check both.
- **Pushed diagnostics identify a file by its name only.** In a pipeline with many identically-named module files (`modules/*/main.nf`), you may not be able to tell which `main.nf` a diagnostic belongs to. In this case, you can run the bundled fallback for repo-relative paths:

  ```bash
  <skill-dir>/scripts/nf-typecheck.sh <project-dir>
  ```

  It drives the same language server headlessly and prints one line per diagnostic, with the path relative to the project root.

Because diagnostics refresh after each edit, detection and verification are the same loop: enable the flag on a file, read the diagnostics, fix, and repeat. Work **outward from the leaves**: type the processes first, then the subworkflows that call them, then the entry workflow and params. A typed process forces its callers to provide correctly-shaped records, so the errors guide you up the call tree.

### Step 2: Fix

For each file, top to bottom:

1. Add `nextflow.enable.types = true`.
2. Convert process/workflow inputs and outputs using the [tables below](#reference-untyped--typed).
3. Replace tuples with records; define shared record types once (see [Record types](#record-types)).
4. Swap legacy operators that don't work under typing (see [Operators](#operators-under-typing)).
5. Apply the **smallest behavior-preserving change** — same files staged, same values emitted. This is not a logic refactor.

### Step 3: Verify

After editing each file, read the diagnostics the language server pushes for it and repeat the fix loop until **no errors or type-mismatch warnings remain** for the files you are migrating — except for the known [acceptable residual warnings](#acceptable-residual-warnings) below. A file is done when it opts into types (`nextflow.enable.types = true`) and reports clean aside from those.

Then confirm behavior is unchanged with the project's tests:

```bash
nf-test test          # if the pipeline uses nf-test
nextflow run . -profile test,docker --outdir results   # otherwise, a test profile run
```

The published output tree and emitted values must match a pre-migration run.

Typing can also **reveal latent bugs** — a mismatch may be a pre-existing bug the type checker exposed, not a regression you introduced. When a diff traces to a genuine semantic difference like this, **flag it for the user to review** rather than reshaping the code to hide it.

### Acceptable residual warnings

Some warnings are **out of scope for a static-typing pass** and should be left in place rather than chased — do not distort the code to silence them:

- **`collectFile` (and any operator not in the typed set).** The typed operators are `collect, combine, filter, flatMap, groupBy, join, map, mix, reduce, subscribe, unique, until, view`. `collectFile` is not among them, so it warns (`incorrect number of arguments`). Resolving it is the job of the separate **[workflow-outputs migration](workflow-outputs.md)**, which comes after this one.
- **Template "unused variable" warnings.** The checker cannot see inside `template` files, so it flags template-only variables as unused (see [Templates are invisible to the type checker](#templates-are-invisible-to-the-type-checker)). Confirm by reading the template, then leave the variable as a bare assignment.

Everything else — type errors and genuine type-mismatch warnings — must be resolved.

## Reference: untyped → typed

### Process inputs

The `input:` section becomes a list of `name: Type` declarations — no `tuple`/`val`/`path` qualifiers.

| Untyped | ✅ Typed |
|---------|---------|
| `val meta` | `meta: Record` |
| `path reads` | `reads: Path` |
| `path "*.fq"` (collection) | `reads: List<Path>` (ordered) / `Bag<Path>` (unordered) / `Set<Path>` |
| `val x` that may be absent | `x: String?` (nullable via `?`) |
| `tuple val(meta), path(reads)` | `record(meta: Record, reads: List<Path>)` |

The `path` qualifier becomes the `Path` **type**; `val` qualifiers drop entirely and you name the concrete type (`String`, `Integer`, `Float`, `Boolean`, `Map`, `List<T>`, …). `Channel` and `Value` are **not** valid input types — those are workflow-level only.

### Process input staging

Staging options that lived on the input qualifier move to a dedicated `stage:` section:

| Untyped | ✅ Typed |
|---------|---------|
| `path(fasta, stageAs: 'tmp/*')` | input `fasta: Path` + `stage: stageAs fasta, 'tmp/*'` |
| `env 'FOO'` | input `foo: String` + `stage: env 'FOO', foo` |
| `stdin` | input `message: String` + `stage: stdin message` |

### Process outputs

A typed process should emit a single **fat record** containing all outputs (the `meta` map, each named file) instead of many skinny tuples. Use `file()` / `files()` instead of the `path` qualifier.

| Untyped | ✅ Typed |
|---------|---------|
| `path "out.txt"` | `file('out.txt')` |
| `path "*.bam"` (collection) | `files('*.bam')` |
| `path "*.log", optional: true` | `file('*.log', optional: true)` |
| `stdout` | `stdout()` |
| `env FOO` | `env('FOO')` |
| `tuple val(meta), path("*.bam"), emit: bam` | `record(meta: meta, bam: file("*.bam"))` |

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

Typed params are an **essential part of this migration**, not an optional extra you can defer. The work is to replace the legacy global `params` object — readable from anywhere — with a typed `params {}` block plus **explicit propagation** down the call tree. Three steps:

1. **Categorize each param by where it's used.** Some params are referenced only in `nextflow.config` (profiles, process directives); others are read in `.nf` script code (workflows, processes). Config-only params stay in config — they are a config concern and are not type-checked the same way. The migration targets the **script-used** params.

2. **Declare the script-used params in a typed `params {}` block** in the **entry-workflow file** (`main.nf`). The block errors anywhere else (`Params block cannot be defined without an entry workflow`). No default = **required** (the run fails if omitted); `?` marks optional; a Boolean with no default defaults to `false`.

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

3. **Propagate params as explicit inputs — do not read the global `params` object inside subworkflows or processes.** Instead, the entry workflow reads the typed params and threads them down through `take:` inputs. Each subworkflow/process receives exactly the params it needs as declared inputs.

   To avoid one `take:` line per param, **bundle related params into a single record** and pass that one record down:

   ```nextflow
   // one record for the param bundle a subworkflow needs
   record AlignerParams {
       aligner: String
       save_reference: Boolean
       clip_r1: Integer
   }
   ```

   The entry workflow constructs the record from the typed params once and passes it as a single input, rather than propagating each field separately.

## Operators under typing

Typed channels carry records, and several legacy operators must be swapped. The full matrix is in the [operators tutorial](https://docs.seqera.io/nextflow/tutorials/static-types-operators).

### Trivial renames

These are direct substitutions:

| Avoid / changed | ✅ Use under typing |
|-----------------|--------------------|
| `Channel.of(...)` (capitalized factory) | `channel.of(...)` — the factory is lowercase |
| `.set { x }` / `.tap { x }` | plain assignment: `x = ch` |
| `.join(other)` | `.join(other, by: 'id')` — `by` is required |
| `.mix(a, b, c)` | chain: `.mix(a).mix(b).mix(c)` |
| implicit closure param `it` | name it: `{ r -> ... }` |
| `.collectFile(...)` | deferred — see [acceptable residual warnings](#acceptable-residual-warnings); fully resolved by the [workflow-outputs migration](workflow-outputs.md) |

The structural transformations below need more than a rename.

### `.out` access — single vs. multi-output

A call's result depends on how many outputs the callee has. This applies to **both processes and workflows**, and single-output is the common case once each process emits one fat record — so you reach for the direct channel far more often than `.out.foo`.

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

`groupBy` takes **no closure** — it groups a channel of `(key, value)` tuples by key. It emits `(key, values)` **tuples**, which you destructure in the next operator. To fix the expected group size (as `groupTuple`'s `size:` did), feed `(key, size, value)` tuples instead.

```nextflow
// ❌ groupTuple
ch.groupTuple()          // or groupTuple(by: 0)

// ✅ groupBy on a channel of (key, value) tuples, then destructure
ch.groupBy()             // emits (key, values) tuples — no closure argument
  .map { key, values -> record(id: key, files: values) }
```

### `.splitCsv()` operator → `.flatMap`

`splitCsv` is not a typed operator, but it remains a **method** on a file. Wrap it in `flatMap`:

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

## Typed stdlib gotchas (script & `exec` bodies)

The operator section above is about *channels*. Most of the actual fix cycles happen **inside** process `script`/`exec` bodies and closures, because Nextflow's typed standard library exposes a **restricted subset** of the underlying Groovy classes — many familiar methods are simply absent. Calling one is a **hard error** (`Unrecognized method '...' for type ...`), not a warning, so expect these when typing bodies that manipulate strings, maps, and paths.

The list below is a starting set of common substitutions (from real migrations) — **not exhaustive**. When you hit an `Unrecognized method`/`Unrecognized property` error, consult the [stdlib-types reference](https://docs.seqera.io/nextflow/reference/stdlib-types) for the typed API. Grow this table as new patterns come up.

| Not available (typed) | Use instead |
|-----------------------|-------------|
| `String.split(sep)` | `String.tokenize(sep)` |
| `Path.toString()` | `"${path}"` |
| `Map.clone()` | `map + [:]` |
| `map << [k: v]` | `map + [k: v]` |
| `Map.putAll(other)` | `map + other` |
| `Map.remove(k)` | `map.subMap(map.keySet() - [k])` |
| `List.unique()` | `list.toUnique()` |
| `List.sort()` | `list.toSorted()` |
| `List.flatten()` | avoid — records are already flat |
| `Channel.distinct()` | `channel.unique()` |

Two collection-shape traps worth calling out:

- **`files("*.ext")` returns a `Set<Path>` (unordered), not a `List`.** A `Set` has no `[]` indexing and no `.first()`/`.find()`. When order matters (read pairs `_1`/`_2`, or any `fastq[0]` access), use **`files("*.ext").toSorted()`** to get an ordered `List<Path>`.
- **`.collect { }` and `.findAll { }` return `Iterable`/`Bag`, not `List`.** If a process input is declared `List<T>`, passing a `.collect { }` result **warns** (`Bag` ≠ `List`). Rework so a `List` isn't required, or convert explicitly. Relatedly, `def x = []` infers `List<E>`, and a later `x = coll.collect { }` then fails (`Iterable` ≠ `List`) — a variable annotation does **not** override the empty-literal inference, so compute the collection in a single expression instead of accumulating into an empty typed local.

## Implicit variables — don't over-add `def`

In general, variables should be declared explicitly with `def`. However, in processes and workflows, variables can be declared without `def` to make them scoped to the entire definition. This is often useful (e.g. a bare variable set in `script:`/`exec:` is visible in the `output:` section as well as `template` files). Only add `def` when the compiler flags it as an error.

## Templates are invisible to the type checker

The type checker cannot see inside `template` files, so it emits false `declared but not used` warnings for variables the template actually uses. Do not delete such a variable on the checker's word alone — **read the template file yourself** and confirm whether it references the variable.

## Critical rules for this migration

1. **STRICT SYNTAX FIRST** — Typed code requires the v2 parser. Run `nextflow lint -o concise .` and resolve all strict-syntax errors (see [strict-syntax.md](strict-syntax.md)) before adding any types.
2. **MIGRATE INCREMENTALLY** — Enable `nextflow.enable.types = true` per file, type the leaf modules first, then work up through subworkflows to the entry workflow. Re-run the type checker after each file.
3. **PREFER RECORDS OVER TUPLES** — Convert `tuple val(meta), path(...)` to records with named, typed fields. Define shared record types once and `include` them. Access fields by name, never by index.
4. **PRESERVE BEHAVIOR** — Same files staged, same values emitted, same conditions. If typing reveals a genuine pre-existing bug or semantic difference, **flag it for the user** rather than reshaping the code to hide it.
5. **SWAP LEGACY OPERATORS** — Replace `set`/`tap`, `.out`, `|`/`&`, `branch`, `multiMap`, `groupTuple`, operator-form `splitCsv`, and capitalized `Channel.` factories per the [operators section](#operators-under-typing).
6. **MIGRATE PARAMS** — Move script-used params into a typed `params {}` block in the entry-workflow file and propagate them as explicit inputs; do not read the global `params` object inside subworkflows/processes.
7. **VERIFY** — After each edit, read the language server's diagnostics (pushed into context by the LSP integration) and fix until no errors or type-mismatch warnings remain, aside from the [acceptable residual warnings](#acceptable-residual-warnings). Then run the project's tests to confirm the output tree and emitted values are unchanged.
