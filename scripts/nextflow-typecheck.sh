#!/usr/bin/env bash
#
# nextflow-typecheck.sh — run the Nextflow language server headlessly and report diagnostics.
#
# `nextflow lint` only does syntax/parse checks; static type checking lives in the
# Nextflow VS Code extension's language server. This script drives that same language
# server over LSP (stdio JSON-RPC) without an editor, so type errors can be collected
# from the command line during the static-typing migration.
#
# What it does:
#   1. Resolves and launches the language server via scripts/nextflow-language-server.sh
#      (the `nextflow-lsp` binary if it's on PATH, else a cached/downloaded jar).
#   2. Initializes the given workspace and pushes config so errors and warnings are reported.
#   3. Opens one .nf (and one .config) file to trigger a full-workspace scan, collects
#      every published diagnostic, then shuts the server down.
#   4. Prints diagnostics grouped by file. Exit code is 1 if any errors were found.
#
# Type checking runs automatically on any .nf file that contains
# `nextflow.enable.types = true`; this script does not enable it for you.
#
# Usage:  nextflow-typecheck.sh [WORKSPACE_DIR]
#
# Requires: jq, plus the launcher's own deps (java 17+; curl or wget).
# Network access on first run (to download the jar).

set -euo pipefail

# Delegate server resolution/launch to the shared launcher.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}"
LAUNCHER="$PLUGIN_ROOT/scripts/nextflow-language-server.sh"

IDLE=3            # seconds of silence that means "scan finished"
FIRST_TIMEOUT=90  # seconds to wait for the first diagnostic before giving up

WORKSPACE="."
for arg in "$@"; do
  case "$arg" in
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) WORKSPACE="$arg" ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "Required tool not found on PATH: jq" >&2; exit 1; }
[[ -x "$LAUNCHER" ]] || { echo "Language server launcher not found or not executable: $LAUNCHER" >&2; exit 1; }

WS_ABS="$(cd "$WORKSPACE" 2>/dev/null && pwd)" || { echo "Not a directory: $WORKSPACE" >&2; exit 1; }

# Settings pushed to the server: WARNINGS mode reports errors plus normal warnings (type
# mismatches surface as warnings); the exclude list also prunes the file search below.
EXCLUDES=(.git .nextflow work .nf-test node_modules .venv)
SETTINGS_JSON="$(jq -cn --args '{nextflow:{errorReportingMode:"WARNINGS",files:{exclude:$ARGS.positional}}}' "${EXCLUDES[@]}")"

# --- launch the server with FIFOs for stdio ---------------------------------
WORKDIR="$(mktemp -d)"
IN="$WORKDIR/in"; OUT="$WORKDIR/out"; DIAGS="$WORKDIR/diags.ndjson"; SERVER_LOG="$WORKDIR/server.log"
mkfifo "$IN" "$OUT"
: > "$DIAGS"

# The launcher resolves the jar and execs it, speaking LSP over stdio.
"$LAUNCHER" < "$IN" > "$OUT" 2>"$SERVER_LOG" &
JPID=$!

cleanup() {
  exec 3>&- 4<&- 2>/dev/null || true
  kill "$JPID" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

exec 3>"$IN"    # writer (held open so the server doesn't see EOF mid-scan)
exec 4<"$OUT"   # reader

# If the launcher/server dies during startup (missing java, bad jar), our first
# writes hit a closed pipe → SIGPIPE. Surface its log instead of dying opaquely (141).
# Cleared before the shutdown sends, where a gone server is expected and harmless.
startup_failed() {
  echo "Language server failed to start:" >&2
  [[ -s "$SERVER_LOG" ]] && sed 's/^/  /' "$SERVER_LOG" >&2
  exit 1
}
trap startup_failed PIPE

# Send a framed LSP message (Content-Length is a BYTE count → measure under LC_ALL=C).
send() {
  local body="$1" len
  len=$(LC_ALL=C printf '%s' "$body" | wc -c)
  printf 'Content-Length: %d\r\n\r\n%s' "$len" "$body" >&3 2>/dev/null
}

ROOT_URI="file://$WS_ABS"

# initialize → initialized → didChangeConfiguration.
# Pushing the settings (a non-default errorReportingMode/exclude) is what makes the server
# (re)scan the workspace.
send "$(jq -cn --arg uri "$ROOT_URI" --arg name "$(basename "$WS_ABS")" \
  '{jsonrpc:"2.0",id:1,method:"initialize",params:{processId:null,rootUri:$uri,capabilities:{workspace:{configuration:false}},workspaceFolders:[{uri:$uri,name:$name}]}}')"
send '{"jsonrpc":"2.0","method":"initialized","params":{}}'
send "$(jq -cn --argjson s "$SETTINGS_JSON" \
  '{jsonrpc:"2.0",method:"workspace/didChangeConfiguration",params:{settings:$s}}')"

# Open one .nf and one .config file — each triggers its service's full-workspace scan.
# Prune the same excluded dirs when hunting for a file to open.
prune=()
for d in ${EXCLUDES[@]+"${EXCLUDES[@]}"}; do
  [[ ${#prune[@]} -gt 0 ]] && prune+=( -o )
  prune+=( -name "$d" )
done
find_first() {  # $1 = filename pattern
  if [[ ${#prune[@]} -gt 0 ]]; then
    find "$WS_ABS" \( "${prune[@]}" \) -prune -o -name "$1" -print 2>/dev/null | head -1
  else
    find "$WS_ABS" -name "$1" -print 2>/dev/null | head -1
  fi
}
open_file() {  # $1 = path, $2 = languageId
  send "$(jq -cn --arg uri "file://$1" --arg lang "$2" --rawfile txt "$1" \
    '{jsonrpc:"2.0",method:"textDocument/didOpen",params:{textDocument:{uri:$uri,languageId:$lang,version:1,text:$txt}}}')"
}
nf="$WS_ABS/main.nf"
[[ -f "$nf" ]] || nf="$(find_first '*.nf')"
cfg="$WS_ABS/nextflow.config"
[[ -f "$cfg" ]] || cfg="$(find_first '*.config')"
[[ -n "$nf"  ]] && open_file "$nf" nextflow
[[ -n "$cfg" ]] && open_file "$cfg" nextflow-config
[[ -z "$nf$cfg" ]] && echo "No .nf or .config files found to scan." >&2

# --- read framed messages until diagnostics go idle ------------------------
# Read bytes (not characters) so multi-byte UTF-8 messages stay aligned with Content-Length.
export LC_ALL=C
got_any=0
start=$SECONDS
while :; do
  clen=0; header_ok=0
  while IFS= read -t "$IDLE" -r line <&4; do
    line=${line%$'\r'}
    if [[ -z "$line" ]]; then header_ok=1; break; fi
    [[ "$line" == Content-Length:* ]] && clen="${line##*: }"
  done
  if [[ $header_ok -eq 0 ]]; then            # idle window elapsed (or EOF)
    [[ $got_any -eq 1 ]] && break
    (( SECONDS - start > FIRST_TIMEOUT )) && break
    continue
  fi
  [[ "$clen" -gt 0 ]] 2>/dev/null || continue
  IFS= read -r -N "$clen" body <&4 || true   # read returns nonzero at EOF even on a full read
  if [[ "$(printf '%s' "$body" | jq -r '.method // empty')" == "textDocument/publishDiagnostics" ]]; then
    printf '%s\n' "$body" >> "$DIAGS"
    got_any=1
  fi
done

trap - PIPE   # past startup; a gone server during shutdown is fine
send '{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}'
send '{"jsonrpc":"2.0","method":"exit","params":null}'
unset LC_ALL

# --- format with jq ---------------------------------------------------------
# Collapse to the latest diagnostics per file (the server may publish a uri twice).
# Write to a file rather than a shell var — the JSON can exceed ARG_MAX on big repos.
BYURI="$WORKDIR/byuri.json"
jq -s 'map(.params) | reduce .[] as $p ({}; .[$p.uri] = $p.diagnostics)' "$DIAGS" > "$BYURI"

lines="$(jq -r --arg root "$ROOT_URI/" '
  to_entries
  | map(.key as $u | (.value // []) | map(. + {uri:$u}))
  | add // []
  | sort_by(.uri, .range.start.line, .range.start.character)
  | .[]
  | ((.uri | ltrimstr($root)) as $r | (if $r == .uri then (.uri | ltrimstr("file://")) else $r end)) as $rel
  | "\($rel):\(.range.start.line + 1):\(.range.start.character + 1): \(["?","error","warning","info","hint"][.severity // 1]): \(.message | gsub("\n";" "))"
' "$BYURI")"

n_err=$(jq -r '[.[][] | select((.severity // 1) == 1)] | length' "$BYURI")
n_warn=$(jq -r '[.[][] | select(.severity == 2)] | length' "$BYURI")

if [[ -n "$lines" ]]; then
  printf '%s\n\n' "$lines"
  files=$(printf '%s\n' "$lines" | sed 's/:.*//' | sort -u | wc -l)
  echo "$n_err error(s), $n_warn warning(s) across $files file(s)."
elif [[ "$got_any" -eq 0 && -s "$SERVER_LOG" ]]; then
  echo "No diagnostics received; the language server may have failed to start:" >&2
  sed 's/^/  /' "$SERVER_LOG" >&2
  exit 1
else
  echo "No diagnostics. ✓"
fi

[[ "$n_err" -gt 0 ]] && exit 1 || exit 0
