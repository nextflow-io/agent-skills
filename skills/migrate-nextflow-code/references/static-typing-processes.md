# Static Typing: Processes

Part of the [static typing migration](static-typing.md). This page covers typing a **process**: its inputs, outputs, and `script`/`exec` body.

## Process inputs

The `input:` section becomes a list of declarations. There are three forms:

```nextflow
input:
meta: Map                      // scalar (name: Type)
reads: Path
record(meta: Map, reads: Path) // destructured record (binds each field directly)
tuple(meta: Map, reads: Path)  // destructured tuple
```

| Untyped | ✅ Typed |
|---------|---------|
| `val meta` | `meta: Map` |
| `path reads` | `reads: Path` |
| `path "*.fq"` (collection) | `reads: List<Path>` (ordered) / `Bag<Path>` (unordered) / `Set<Path>` |
| Optional input | `name: Type?` (nullable via `?`) |

- The `path` qualifier becomes the `Path` **type**
- `val` qualifiers are replaced by a concrete type (`String`, `Integer`, `Float`, `Boolean`, `Map`, `List<T>`, …)
- `Channel` and `Value` are **not** valid input types — those are workflow-level only.

### Migrate tuple inputs to records

`tuple(...)` and `record(...)` are **distinct types** — a `tuple(meta: Map, reads: List<Path>)` input (typed `Tuple<...>`) will **not** accept a `record(...)` value (typed `Record`), and vice versa. So migrate the input from a tuple to a record:

```nextflow
// legacy tuple input
tuple val(meta), path(reads)

// typed tuple input
tuple(meta: Map, reads: List<Path>)

// ✅ migrated to a record input — connects to record channels
record(meta: Map, reads: List<Path>)
```

Both bind `meta` and `reads` the same way in the script body; only the type changes. Prefer the record form everywhere the channel carries records.

## Process input staging

Staging options that lived on the input qualifier move to a dedicated `stage:` section:

| Untyped | ✅ Typed |
|---------|---------|
| `path(fasta, stageAs: 'tmp/*')` | input `fasta: Path` + `stage: stageAs fasta, 'tmp/*'` |
| `env 'FOO'` | input `foo: String` + `stage: env 'FOO', foo` |
| `stdin` | input `message: String` + `stage: stdin message` |

## Process outputs

A typed process should emit a single **fat record** containing all outputs (the `meta` map, each named file) instead of many skinny tuples. Use `file()` / `files()` instead of the `path` qualifier.

| Untyped | ✅ Typed |
|---------|---------|
| `path "out.txt"` | `file('out.txt')` |
| `path "*.txt"` (collection) | `files('*.txt')` |
| `path "*.log", optional: true` | `file('*.log', optional: true)` |
| `stdout` | `stdout()` |
| `env 'FOO'` | `env('FOO')` |

Migrate multiple skinny tuples to a single fat record:

```nextflow
// before
tuple val(meta), path("*.bam"), emit: bam
tuple val(meta), path("*.bai"), emit: bai

// after
record(meta: meta, bam: file("*.bam"), bai: file("*.bai"))
```

## Versions and the `topic:` section

Outputs with a `topic:` qualifier become **topic emissions**. Move them to the `topic:` section and use `>>` to emit to the desired topic:

```nextflow
topic:
file("versions.yml") >> 'versions'
tuple(task.process, 'tool-name', eval('tool-version')) >> 'versions'
```

Collect them in the entry workflow with `channel.topic('versions')` instead of threading a `ch_versions` channel through every call. This also lets you delete the `ch_versions = ch_versions.mix(...)` plumbing.

`channel.topic('versions')` has an **unknown element type** — the type checker cannot infer it from the emissions, even though you know what each process emitted. Cast each element to the appropriate type when mapping over it.

```nextflow
// file emissions
channel.topic('versions').map { v -> v as Path }

// (process, tool, version) tuple emissions — cast to Tuple, then the map
// closure can destructure it directly
channel.topic('versions')
    .map { v -> v as Tuple<String,String,String> }
    .map { process, tool, version -> tuple(process.tokenize(':').last(), "  ${tool}: ${version}") }
```

## The `when:` block

Typed processes drop the `when: task.ext.when` idiom.

## Standard library gotchas

The Nextflow standard library exposes a **restricted subset** of the underlying Groovy classes — many methods from Groovy are not supported under static typing. As a result, you may encounter `Unrecognized method`/`Unrecognized property` errors when migrating code that manipulates standard types such as lists, maps, and strings.

The following is a working list of common substitutions (from real migrations, not exhaustive). See the [standard types reference](https://docs.seqera.io/nextflow/reference/stdlib-types) for the comprehensive API.

| Legacy pattern | Use instead |
|----------------|-------------|
| `list.flatten()` | `list.collectMany()` |
| `list.sort()` | `list.toSorted()` |
| `list.unique()` | `list.toUnique()` |
| `map.clone(); map << [k: v]` | `map += [k: v]` |
| `map.putAll(other)` | `map + other` |
| `map.remove(k)` | `map.subMap(map.keySet() - [k])` |
| `string.split(sep)` | `string.tokenize(sep)` |
| `string.split(/regex/)` | `string.replaceAll(/…/, '…').tokenize(sep)` |
| `x.toString()` | `"${x}"` |
| '"' + x + '"' | `"\"${x}\""`
| `task.memory.giga` / `.mega` | `task.memory.toGiga()` / `toMega()` |

Additional gotchas worth calling out:

- **`files("...")` returns a `Set<Path>` (unordered), not a `List`.** A `Set` has no `[]` indexing and no `.first()`. When order matters (read pairs `_1`/`_2`, or any `fastq[0]` access), use **`files("...").toSorted()`** to get an ordered `List<Path>`.

- **The `collect()` operator returns `Value<Bag>` (unordered), not a `List`.** If a process input (or other consumer) is declared `List<T>`, feeding it a `collect()` result is a type mismatch (`Bag` ≠ `List`). Either convert the bag to a list with `toSorted()`, declare the consumer as `Bag<T>`.

- **The `collect { }` and `findAll { }` iterable methods return an `Iterable`, not a `List`.** Convert with `toSorted()` (or `toList()` if you know the source is a list). For example, `def x = []` infers `List<E>`, so a later `x = coll.collect { }` fails (`Iterable` ≠ `List`) — use `coll.collect { }.toList()` instead.

## Implicit variables and `def`

In general, variables should be declared explicitly with `def`. However, in processes and workflows, variables can be declared without `def` to make them scoped to the entire definition. This is often useful (e.g. a bare variable set in `script:`/`exec:` is visible in the `output:` section as well as `template` files). Only add `def` when the compiler flags it as an error.

## Templates and false warnings

The compiler cannot see inside `template` files, so it may report false `declared but not used` warnings for variables used by the template. **Read the template file yourself** to determine which variables it uses, and make sure those variables are declared without `def` so that they are visible to the template.
