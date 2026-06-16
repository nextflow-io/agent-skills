#!/usr/bin/env bash
# PostToolUse companion: record .nf/.config files Claude just edited so the
# Stop hook can lint them once on the final state.
set -euo pipefail

# Bail silently if jq isn't available (macOS ships without it).
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

[ -n "$session_id" ] && [ -n "$file_path" ] || exit 0

case "$file_path" in
  *.nf | *.config) ;;
  *) exit 0 ;;
esac

state_dir="${TMPDIR:-/tmp}/claude-nextflow-lint"
mkdir -p "$state_dir"
printf '%s\n' "$file_path" >> "${state_dir}/${session_id}.list"
