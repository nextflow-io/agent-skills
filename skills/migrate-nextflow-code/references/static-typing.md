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
2. **This is a large, invasive migration.** Converting tuples to records reshapes channels, inputs, outputs, and the operators between them. Do it **incrementally**, one file at a time, enabling the feature flag and solving type errors per file, rather than flipping everything at once.
3. **Records are the point.** The payoff is replacing `tuple val(meta), path(...)` with records whose fields have names and types (`sample.id`, `sample.bam`).

## Type checking

Static typing is enabled per-script by enabling a feature flag at the top:

```nextflow
nextflow.enable.types = true
```

Type checking is provided by the Nextflow language server, which is included in this plugin.

- After you edit a `.nf` or `nextflow.config` file, you will receive diagnostics automatically.
- Some type mismatches are reported as errors while others are reported as warnings -- make sure to check both.
- **Hover a variable or call site to see its inferred type.** The language server serves type hints over LSP hover — use them to inspect a value whose type isn't obvious from the code, e.g. which fields a bare `Record` actually carries. This tells you what the type checker sees, which is faster than guessing when a type mismatch occurs.
- **Pushed diagnostics identify a file by its name only.** In a pipeline with many identically-named module files (`modules/*/main.nf`), you may not be able to tell which `main.nf` a diagnostic belongs to. In this case, you can run the bundled fallback for repo-relative paths:

  ```bash
  <skill-dir>/scripts/nf-typecheck.sh <project-dir>
  ```

  It drives the same language server headlessly and prints one line per diagnostic, with the path relative to the project root.

## The migration loop

For each file:

1. Add `nextflow.enable.types = true`.
2. Migrate the script definitions following the [reference pages](#reference-pages) below.
3. Replace tuples with records; define record types as needed (see [Record types](#record-types)).
4. Read the diagnostics, fix, and repeat.

Work **outward from the leaves**: type the processes first, then the subworkflows that call them, then the entry workflow and params. A typed process forces its callers to provide correctly-shaped records, so the errors guide you up the call tree.

Apply the **smallest behavior-preserving change** — same files staged, same values emitted. This is not a logic refactor.

Keep fixing the diagnostics until **no errors or type-mismatch warnings remain** — except for the [acceptable residual warnings](#acceptable-residual-warnings) below.

Finally, confirm behavior is unchanged by performing a test run:

```bash
# profile names and params may vary by pipeline
nextflow run . -profile test,docker --outdir results
```

The output directory (`results`) must match a pre-migration run.

Typing can also **reveal latent bugs** — a mismatch may be a pre-existing bug the type checker exposed, not a regression you introduced. When a diff traces to a genuine semantic difference like this, **flag it for the user to review** rather than reshaping the code to hide it.

### Acceptable residual warnings

Some warnings are **out of scope for a static-typing migration** and may be left in place rather than chased — do not distort the code to silence them.

#### collectFile

The typed operators are `collect, combine, filter, flatMap, groupBy, join, map, mix, reduce, subscribe, unique, until, view`. ALl other operators are discouraged from use with static typing, including `collectFile`. However, `collectFile` is handled by the **[workflow-outputs migration](workflow-outputs.md)**, which comes after this one.

#### Process templates

The type checker cannot see inside `template` files, so it flags template-only variables as unused (see [Templates and false warnings](static-typing-processes.md#templates-and-false-warnings)). Confirm by reading the template, then leave the variable as a bare assignment.

## Reference pages

Load the page for what you're typing (working **outward from the leaves**, as above):

| Typing a… | Read | Covers |
|-----------|------|--------|
| **process** | [static-typing-processes.md](static-typing-processes.md) | inputs, staging, outputs (fat records), `topic:`/versions, stdlib gotchas |
| **workflow** | [static-typing-workflows.md](static-typing-workflows.md) | `take:`/`emit:` types, channel operator swaps |
| **params** | [static-typing-params.md](static-typing-params.md) | typed `params {}` block, propagation as inputs |

[Record types](#record-types) are shared by all three.

## Record types

Record types can be defined and included across scripts as follows:

```nextflow
// utils/types.nf
record Sample {
    id: String
    meta: Record
    reads: List<Path>
}
```

```nextflow
// main.nf
include { Sample } from './utils/types.nf'
```

Use `record(field: value, ...)` to construct a record and `r + record(extra: v)` to add fields. Access fields by name (`sample.id`).

Records are **duck-typed**: a value satisfies a record type if it has at least the declared fields. The type checker will tell you if a call site has a record mismatch.

## Critical rules for this migration

1. **STRICT SYNTAX FIRST** — Static typing requires the v2 parser. Run `nextflow lint -o concise .` and resolve all strict-syntax errors (see [strict-syntax.md](strict-syntax.md)) before adding any types.
2. **MIGRATE INCREMENTALLY** — Enable `nextflow.enable.types = true` per file, type the leaf modules first, then work up through subworkflows to the entry workflow. Fix type errors as you go.
3. **PREFER RECORDS OVER TUPLES** — Convert `tuple val(meta), path(...)` to records with named, typed fields. Use explicit record types as needed at component boundaries. Access fields by name, never by index.
4. **SWAP LEGACY OPERATORS** — Replace `set`/`tap`, `.out`, `|`/`&`, `branch`, `multiMap`, `groupTuple`, operator-form `splitCsv`, and capitalized `Channel.` factories per the [operator guidelines](static-typing-workflows.md#operators-under-typing).
5. **MIGRATE PARAMS** — Move script-used params into a typed `params {}` block alongside the entry workflow and propagate them as explicit inputs; do not use the global `params` object inside subworkflows/processes.
