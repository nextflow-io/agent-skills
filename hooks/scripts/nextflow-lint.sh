#!/usr/bin/env bash
# PostToolUse hook: lint Nextflow files after Claude writes or edits them.
# Surfaces `nextflow lint` errors back to Claude (exit 2) so it can self-correct.
set -euo pipefail

input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

[ -n "$file_path" ] || exit 0

case "$file_path" in
  *.nf | *.config) ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0

# Skip silently if Nextflow isn't installed; the install-nextflow skill covers setup.
command -v nextflow >/dev/null 2>&1 || exit 0

if output="$(nextflow lint "$file_path" 2>&1)"; then
  exit 0
fi

{
  echo "nextflow lint reported issues in ${file_path}:"
  echo "$output"
  echo
  echo "Fix the lint errors above."
} >&2
exit 2
