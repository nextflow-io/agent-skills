#!/usr/bin/env bash
# PostToolUse hook (asyncRewake): lint a single Nextflow file Claude just
# edited. The hook `if` patterns already scope this to .nf/.config files, so no
# extension check is needed here. Runs in the background; on a lint failure,
# exit 2 surfaces the output to Claude as a system reminder to fix, without
# blocking. Skips silently when jq or nextflow is unavailable.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v nextflow >/dev/null 2>&1 || exit 0

file_path="$(jq -r '.tool_input.file_path // empty')"
[ -n "$file_path" ] && [ -f "$file_path" ] || exit 0

if output="$(nextflow lint "$file_path" 2>&1)"; then
  exit 0
fi

{
  echo "nextflow lint found issues in ${file_path}:"
  echo "$output"
  echo
  echo "Fix the lint errors above."
} >&2
exit 2
