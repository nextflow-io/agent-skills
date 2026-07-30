---
description: Evaluate the migrate-nextflow-code skill
argument-hint: <strict-syntax|topic-channels|static-typing|workflow-outputs> <github-url> [branch]
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Skill
---

Evaluate the `migrate-nextflow-code` skill by attempting a real migration on a real Nextflow pipeline.

Arguments:
- `$1` — which migration to evaluate: one of `strict-syntax`, `topic-channels`, `static-typing`, `workflow-outputs` (required)
- `$2` — GitHub URL of the pipeline to migrate (required)
- `$3` — branch to check out (optional; default branch if omitted)

If `$1` is not one of the three migrations above, stop and say so — do not guess.

Do this in order:

1. **Read the skill.** Read `skills/migrate-nextflow-code/SKILL.md`, then the reference file for the `$1` migration. Follow that procedure — do not improvise your own migration steps.

2. **Clone into `evals/`.** Clone the repository as `evals/<name>` (add `--branch $3` if a branch was given). If `evals/<name>` already exists, stop and ask whether to reuse it or re-clone — do not silently overwrite. Change into the directory.

3. **Run the `$1` migration.** Perform the `$1` migration on `evals/<name>`.

4. **Report the outcome.** When done (or blocked), summarize as an eval result:
   - how far the migration got;
   - anything the skill's instructions didn't cover or got wrong, and any point where a tool's output was stale, missing, or misleading.
