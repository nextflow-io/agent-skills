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

`nextflow lint` only does syntax checks — it will **not** report type errors. Type checking is provided by the Nextflow language server, which the plugin bundles as a script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/nextflow-typecheck.sh <project-dir>
```

It runs the language server headlessly over the whole project and prints one line per diagnostic, with the path relative to the project root. Exit code is 1 if any errors were found. Run it after each round of edits — it is the only way to see type errors.

- It requires `jq` and Java 17+.
- Some type mismatches are reported as errors while others are reported as warnings — make sure to check both.
- The first run downloads the language server jar (~1 min); later runs reuse the cached jar. A full scan takes a few seconds to a minute depending on project size, so batch your edits rather than re-running it after every single change.

## The migration loop

For each file:

1. Add `nextflow.enable.types = true`.
2. Migrate the script definitions following the [reference pages](#reference-pages) below.
3. Replace tuples with records; define record types as needed.
4. Run `nextflow-typecheck.sh`, read the diagnostics, fix, and repeat.

Work **outward from the leaves**: type the processes first, then the subworkflows that call them, then the entry workflow and params. A typed process forces its callers to provide correctly-shaped records, so the errors guide you up the call tree.

Apply the **smallest behavior-preserving change** — same files staged, same values emitted. This is not a logic refactor.

Keep fixing the diagnostics until **no errors or type-mismatch warnings remain** — except for the [acceptable residual warnings](#acceptable-residual-warnings) below.

Finally, confirm behavior is unchanged by performing a test run:

```bash
# profile names and params may vary by pipeline
nextflow run . -profile test,docker --outdir results -resume
```

The output directory (`results`) must match a pre-migration run.

Typing can also **reveal latent bugs** — a mismatch may be a pre-existing bug the type checker exposed, not a regression you introduced. When a diff traces to a genuine semantic difference like this, **flag it for the user to review** rather than reshaping the code to hide it.

### Acceptable residual warnings

Some warnings are **out of scope for a static-typing migration** and may be left in place rather than chased — do not distort the code to silence them.

#### collectFile

`collectFile` is not a typed operator (see the [operator list](static-typing-workflows.md#dataflow-logic)), so it warns under typing. It is handled by the **[workflow-outputs migration](workflow-outputs.md)**, which comes after this one — leave it for now.

#### Process templates

The type checker cannot see inside `template` files, so it flags template-only variables as unused (see [Templates and false warnings](static-typing-processes.md#templates-and-false-warnings)). Confirm by reading the template, then leave the variable as a bare assignment.

## Reference pages

Load the page for what you're typing (working **outward from the leaves**, as above):

| Typing a… | Read | Covers |
|-----------|------|--------|
| **process** | [static-typing-processes.md](static-typing-processes.md) | inputs, staging, outputs (fat records), `topic:`/versions, stdlib gotchas |
| **workflow** | [static-typing-workflows.md](static-typing-workflows.md) | `take:`/`emit:` types, channel operator swaps |
| **params** | [static-typing-params.md](static-typing-params.md) | typed `params {}` block, propagation as inputs |

## Type casting

You can use the cast (`as`) operator to coerce the type of an expression to satisfy the type checker while migrating code. However, type casting should be avoided in the final code except where there is explicit guidance for it (`splitCsv`, topic channel values). Aside from these limited cases, you should never need to use type casts on a fully migrated pipeline.

## Critical rules for this migration

1. **STRICT SYNTAX FIRST** — Static typing requires the v2 parser. Run `nextflow lint -o concise .` and resolve all strict-syntax errors (see [strict-syntax.md](strict-syntax.md)) before adding any types.
2. **MIGRATE INCREMENTALLY** — Enable `nextflow.enable.types = true` per file, type the leaf modules first, then work up through subworkflows to the entry workflow. Fix type errors as you go.
3. **MIGRATE TUPLES TO RECORDS** — Convert `tuple val(meta), path(...)` to records with named, typed fields. Use explicit record types as needed at component boundaries. Access fields by name, never by index.
4. **MIGRATE LEGACY OPERATORS** — Replace `set`/`tap`, `.out`, `|`/`&`, `branch`, `multiMap`, `groupTuple`, operator-form `splitCsv`, and capitalized `Channel.` factories per the [operator guidelines](static-typing-workflows.md#dataflow-logic).
5. **MIGRATE PARAMS** — Move script-used params into a typed `params {}` block alongside the entry workflow and propagate them as explicit inputs; do not use the global `params` object inside subworkflows/processes.
