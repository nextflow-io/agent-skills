# Strict Syntax Migration

Nextflow 26.04 makes the **strict syntax parser** the default. Code that parsed under the legacy parser may now be rejected or flagged. The goal of this migration is to make the pipeline parse cleanly under strict syntax **without changing its behavior**.

Reference:
- https://docs.seqera.io/nextflow/reference/syntax
- https://docs.seqera.io/nextflow/strict-syntax

## The loop: detect → fix → verify

### Step 1: Detect

Run the linter over the project. It parses every `.nf` script and `.config` file and reports errors and warnings:

```bash
nextflow lint -o concise .
```

- `-o concise` is best for triage (one line per issue). Use `-o full` to see the offending code in context, or `-o json` to process programmatically.
- Lint specific paths instead of the whole project: `nextflow lint main.nf workflows/ subworkflows/`.
- `.git`, `.nextflow`, `.nf-test`, `work`, etc. are excluded by default; add more with `-exclude`.

### Step 2: Fix

Work through the reported issues using the [reference table](#reference-strict-syntax-fixes) below. For each one:

1. Read the file and locate the flagged line.
2. Apply the **smallest behavior-preserving change** that resolves it.
3. Do not refactor unrelated code, rename things gratuitously, or "improve" logic — this migration is about parser compatibility only.

### Step 3: Verify

Re-run `nextflow lint -o concise .` after each batch of fixes and repeat until there are **zero errors**.

Finally, confirm behavior is unchanged. Prefer the project's own test suite:

```bash
nf-test test          # if the pipeline uses nf-test
nextflow run . -profile test,docker --outdir results   # otherwise, a test profile run
```

## Reference: strict syntax fixes

These are the common errors the strict parser raises and their behavior-preserving fixes.

### Removed — must be rewritten

| Pattern | ❌ Not allowed | ✅ Fix |
|---------|---------------|--------|
| `import` statements | `import groovy.json.JsonSlurper` | Use the fully qualified name inline: `new groovy.json.JsonSlurper()` |
| Top-level statements mixed with declarations | bare statements beside `process`/`workflow` defs | Move statements into the entry `workflow { }` |
| Top-level workflow handlers | `workflow.onComplete { ... }` at script level | Assign inside the entry workflow: `workflow { workflow.onComplete = { ... } }` |
| Assignment in an expression | `hello(x = 1)`, `f(x++)` | Assign first: `x = 1; hello(x)` / `x += 1; f(x)` |
| `for` / `while` loops | `for (x in list) { ... }` | Higher-order functions: `list.each { x -> ... }`, `.collect { }`, `.find { }` |
| `switch` statements | `switch (v) { case 'a': ... }` | `if`/`else if`/`else` chain |
| Spread operator | `[meta, *bambai]` | Enumerate: `[meta, bambai[0], bambai[1]]`, or destructure: `def (a, b) = list` |
| Implicit env vars | `"PWD = ${PWD}"` | `"PWD = ${env('PWD')}"` (or `System.getenv('PWD')`) |
| Closure variable called like a function | `def func = { ... }` inside process/workflow, called as `func(x)` | Promote to a top-level `def func(x) { ... }` function |

### Restricted — limited forms only

| Pattern | ❌ Not allowed | ✅ Fix |
|---------|---------------|--------|
| `addParams` / `params` in includes | `include { f } from './m' addParams(x: 1)` | Pass values as explicit workflow/process inputs |
| Typed / multi / `final` var declarations | `String s = 'x'`, `def a = 1, b = 2`, `final n = 1` | `def s = 'x'`; one `def` per variable; (typed `def s: String = 'x'` allowed in 25.10+) |
| Interpolated slashy / dollar-slashy strings | `/${id}\.bam/`, `$/.../$` | Double-quoted: `"${id}\\.bam"`, or triple-quoted `""" ... """` |
| Soft casts | `(Map) x` | Hard cast `x as Map`, or a method like `'42'.toInteger()` |
| Unquoted process `env` in/out | `env FOO` | `env 'FOO'` |
| Missing `script:` label | input section but no `script:` | Add the `script:` label when other sections are present |

### Deprecated — warnings, fix while you are here

Always fix the following deprecation warnings. Other warnings don't need to be fixed unless it is convenient or the user asks.

| Pattern | ❌ Avoid | ✅ Prefer |
|---------|---------|-----------|
| Capitalized channel factory | `Channel.of(...)` | `channel.of(...)` (lowercase namespace) |
| Implicit closure parameter | `ch.map { it * 2 }` | `ch.map { v -> v * 2 }` |
| Process `shell:` section | `shell:` with `!{var}` | `script:` section with `${var}` |

### Config files

| Pattern | ❌ Not allowed | ✅ Fix |
|---------|---------------|--------|
| `if` statements / function defs at top level | `if (params.x) { process { ... } }` | Use a ternary on the setting (`containerOptions = params.use_spark ? '' : null`), or per-process selectors — the strict parser validates selectors against conditional processes, so the guard is usually unnecessary |
| Conditional `includeConfig` | `if (c) includeConfig 'a.config'` | Dynamic include with a closure: `includeConfig ({ c ? 'a.config' : 'b.config' }())` |
| Referencing non-`params` config settings as variables | `subnetwork = "regions/${google.location}/.."` | Route through `params`: set `params.location` and reference that |

## Gotchas from real migrations

- **A closure variable cannot share a name with a variable in the workflow definition.** The strict parser treats this as a shadowing conflict. Rename the closure parameter (e.g. `reads` → `reads_`) rather than the channel.
- **Most config `if` statements can simply be deleted, not rewritten.** Because the strict parser validates process selectors even for conditionally-included processes, the protective `if` wrapper around a process-selector config block is usually redundant. (Seen in [nf-core/sarek#2159](https://github.com/nf-core/sarek/pull/2159).)
- **CLI params are no longer auto-cast.** With the strict parser, `--flag false` arrives as the string `'false'` (which is truthy). Convert explicitly (`params.flag.toBoolean()`) or declare a typed `params` block. Watch for this when behavior changes after migration even though parsing succeeds.

## Escape hatch: `lib/` directory

If a piece of Groovy genuinely cannot be expressed in strict syntax (complex classes, third-party library use), move it into the project's **`lib/` directory**, where full Groovy is still allowed, and call it from the pipeline.

Reach for this only after confirming the construct can't be rewritten with the table above — most code can.

## Critical rules for this migration

1. **DETECT FIRST** — Always run `nextflow lint -o concise .` to enumerate the actual errors before changing anything. Never guess at what needs fixing.
2. **PRESERVE BEHAVIOR** — This migration is about parser compatibility, not refactoring. Apply the smallest change that resolves each error; do not alter pipeline logic.
3. **LOOP UNTIL CLEAN** — Re-run the linter after each batch of fixes and repeat until zero errors remain.
4. **VERIFY** — Run the project's tests (`nf-test test` or a `-profile test` run) to confirm behavior is unchanged before declaring the migration done.
5. **USE THE ESCAPE HATCH SPARINGLY** — Move code to `lib/` only when it truly cannot be expressed in strict syntax.
6. **WATCH FOR SILENT BEHAVIOR CHANGES** — CLI params are no longer auto-cast; verify boolean/numeric params still behave correctly after migration.
