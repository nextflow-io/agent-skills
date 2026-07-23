# Static Typing: Params

Part of the [static typing migration](static-typing.md). This page covers migrating params.

Typed params are an **essential part of this migration**, not an optional extra you can defer. The work is to replace the legacy global `params` object — readable from anywhere — with a typed `params {}` block plus **explicit propagation** down the call tree. Three steps:

1. **Categorize each param by where it's used.** Some params are referenced only in `nextflow.config` (profiles, process directives); others are read in `.nf` script code (workflows, processes). Config-only params stay in config — they are a config concern and are not type-checked the same way. The migration targets the **script-used** params.

   The config `params {}` block and the script `params {}` block are **complementary sources of truth** — config params for the config file, script params for the script — so expect the two blocks to coexist rather than deduplicate them. `nextflow_schema.json` is a JSON-schema representation of the *combined* params; leave it in place (it still drives external tooling).

2. **Declare the script-used params in a typed `params {}` block** in the **entry-workflow file** (`main.nf`). No default = **required** (the run fails if omitted); `?` marks optional; a Boolean with no default defaults to `false`.

   ```nextflow
   params {
       input: String                // required
       outdir: Path = 'results'     // default
       fasta: Path?                 // optional
       aligner: String = 'bismark'
       save_reference: Boolean      // defaults to false
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

   workflow ALIGNER {
       take:
       // ...
       params: AlignerParams

       // ...
   }
   ```

   As long as this record is a strict subset of the `params` block, you can pass the `params` object as the record input — no need to construct a new record or pass each param separately.
