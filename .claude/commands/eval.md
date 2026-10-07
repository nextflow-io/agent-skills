---
description: Evaluate the migrate-nextflow-code skill
argument-hint: <github-url> [branch] <description>
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
---

Clone a Nextflow pipeline. Have a subagent migrate it using the `/migrate-nextflow-code` skill and report back on its experience with the skill.

Arguments:
- `$1` — GitHub URL of the pipeline to migrate (required)
- `$2` — branch to check out (optional)
- `$3` — description of the migration to perform (required)

Procedure:

1. Clone the pipeline repository into the `evals` directory as `evals/<name>-<NNN>`, where `NNN` is zero-padded increment to distinguish between repeated runs on the same pipeline. If a branch is not given, use the `dev` branch if the project has one, otherwise the default branch.

2. Prompt a subagent with the repo, the skill, and the migration to perform.

3. Have the agent report on its experience using the skill: how the migration went, what external resources it used, what worked or didn't work, etc. The agent should write a detailed `REPORT.md` to the repository, with inline code snippets as needed to explain issues. Offer to ask the agent follow-up questions if you have the tools to do so.
