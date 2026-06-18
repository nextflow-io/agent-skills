#!/usr/bin/env bash
# Stop hook (asyncRewake): lint the .nf/.config files edited during this turn,
# once, on their final state. Single JVM startup; no work-in-progress false
# positives. Runs in the background so it never delays the user getting control
# back; on exit 2 its stderr is surfaced to Claude as a system reminder to fix.
set -euo pipefail

# Skip silently if prerequisites are missing rather than spam every Stop event.
command -v jq >/dev/null 2>&1 || exit 0
command -v nextflow >/dev/null 2>&1 || exit 0

input="$(cat)"

# Avoid re-entry loops: if Claude is already in a stop-blocked iteration, let
# it stop now rather than block again.
if [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ]; then
  exit 0
fi

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
[ -n "$session_id" ] || exit 0

state_dir="${TMPDIR:-/tmp}/claude-nextflow-lint"
state_file="${state_dir}/${session_id}.list"
[ -f "$state_file" ] || exit 0

# Read unique files that still exist on disk; always clear the state file so
# the next turn starts fresh.
files=()
while IFS= read -r f; do
  [ -f "$f" ] && files+=("$f")
done < <(sort -u "$state_file")
rm -f "$state_file"

[ "${#files[@]}" -gt 0 ] || exit 0

if output="$(nextflow lint "${files[@]}" 2>&1)"; then
  exit 0
fi

{
  echo "nextflow lint found issues in files edited in the last turn:"
  echo "$output"
  echo
  echo "Fix the lint errors above."
} >&2
exit 2
