#!/usr/bin/env bash
#
# nf-typecheck.sh — run the Nextflow language server headlessly and report diagnostics.
#
# `nextflow lint` only does syntax/parse checks; static type checking lives in the
# Nextflow VS Code extension's language server. This script drives that same language
# server over LSP (stdio JSON-RPC) without an editor, so type errors can be collected
# from the command line during the static-typing migration.
#
# What it does:
#   1. Ensures the language server jar is at ~/.nextflow/lsp/v26.04/language-server-all.jar
#      (downloads the latest v26.04.x release from GitHub if missing).
#   2. Launches it, initializes the given workspace, and pushes config so errors and
#      warnings are reported.
#   3. Opens one .nf (and one .config) file to trigger a full-workspace scan, collects
#      every published diagnostic, then shuts the server down.
#   4. Prints diagnostics grouped by file. Exit code is 1 if any errors were found.
#
# Type checking runs automatically on any .nf file that contains
# `nextflow.enable.types = true`; this script does not enable it for you.
#
# Usage:  nf-typecheck.sh [WORKSPACE_DIR]
#
# Requires: java (17+), jq, curl. Network access on first run (to download the jar).

set -euo pipefail

LSP_DIR="$HOME/.nextflow/lsp/v26.04"
JAR="$LSP_DIR/language-server-all.jar"
RELEASES_API="https://api.github.com/repos/nextflow-io/language-server/releases"
FALLBACK_URL="https://github.com/nextflow-io/language-server/releases/download/v26.04.1/language-server-all.jar"

# Directories never worth scanning (large / generated).
EXCLUDE_JSON='[".git",".nextflow","work",".nf-test","node_modules",".venv"]'

IDLE=3            # seconds of silence that means "scan finished"
FIRST_TIMEOUT=90  # seconds to wait for the first diagnostic before giving up

WORKSPACE="."
for arg in "$@"; do
  case "$arg" in
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) WORKSPACE="$arg" ;;
  esac
done

for tool in java jq curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Required tool not found on PATH: $tool" >&2; exit 1; }
done

WS_ABS="$(cd "$WORKSPACE" 2>/dev/null && pwd)" || { echo "Not a directory: $WORKSPACE" >&2; exit 1; }

# --- ensure the jar is present ----------------------------------------------
if [[ ! -f "$JAR" ]]; then
  mkdir -p "$LSP_DIR"
  url="$(curl -fsSL "$RELEASES_API" 2>/dev/null | jq -r '
      [ .[]
        | select(.tag_name | startswith("v26.04."))
        | { patch: (.tag_name | split(".") | last | tonumber),
            url:   (.assets[] | select(.name == "language-server-all.jar") | .browser_download_url) } ]
      | max_by(.patch) | .url // empty' || true)"
  [[ -n "$url" ]] || url="$FALLBACK_URL"
  echo "Downloading language server: $url" >&2
  curl -fsSL "$url" -o "$JAR"
  echo "Saved to $JAR" >&2
fi

# --- launch the server with FIFOs for stdio ---------------------------------
WORKDIR="$(mktemp -d)"
IN="$WORKDIR/in"; OUT="$WORKDIR/out"; DIAGS="$WORKDIR/diags.ndjson"
mkfifo "$IN" "$OUT"
: > "$DIAGS"

java -jar "$JAR" < "$IN" > "$OUT" 2>/dev/null &
JPID=$!

cleanup() {
  exec 3>&- 4<&- 2>/dev/null || true
  kill "$JPID" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

exec 3>"$IN"    # writer (held open so the server doesn't see EOF mid-scan)
exec 4<"$OUT"   # reader

# Send a framed LSP message (Content-Length is a BYTE count → measure under LC_ALL=C).
send() {
  local body="$1" len
  len=$(LC_ALL=C printf '%s' "$body" | wc -c)
  printf 'Content-Length: %d\r\n\r\n%s' "$len" "$body" >&3
}

ROOT_URI="file://$WS_ABS"

# initialize → initialized → didChangeConfiguration.
# Settings MUST be nested objects (the server navigates dotted keys), and a non-default
# errorReportingMode/exclude is what makes it (re)scan the workspace. WARNINGS reports
# errors plus normal warnings (type mismatches surface as warnings).
send "$(jq -cn --arg uri "$ROOT_URI" --arg name "$(basename "$WS_ABS")" \
  '{jsonrpc:"2.0",id:1,method:"initialize",params:{processId:null,rootUri:$uri,capabilities:{workspace:{configuration:false}},workspaceFolders:[{uri:$uri,name:$name}]}}')"
send '{"jsonrpc":"2.0","method":"initialized","params":{}}'
send "$(jq -cn --argjson ex "$EXCLUDE_JSON" \
  '{jsonrpc:"2.0",method:"workspace/didChangeConfiguration",params:{settings:{nextflow:{errorReportingMode:"WARNINGS",files:{exclude:$ex}}}}}')"

# Open one .nf and one .config file — each triggers its service's full-workspace scan.
prune=( -name .git -o -name .nextflow -o -name work -o -name .nf-test -o -name node_modules )
open_file() {  # $1 = path, $2 = languageId
  send "$(jq -cn --arg uri "file://$1" --arg lang "$2" --rawfile txt "$1" \
    '{jsonrpc:"2.0",method:"textDocument/didOpen",params:{textDocument:{uri:$uri,languageId:$lang,version:1,text:$txt}}}')"
}
nf="$WS_ABS/main.nf"
[[ -f "$nf" ]] || nf="$(find "$WS_ABS" \( "${prune[@]}" \) -prune -o -name '*.nf' -print 2>/dev/null | head -1)"
cfg="$WS_ABS/nextflow.config"
[[ -f "$cfg" ]] || cfg="$(find "$WS_ABS" \( "${prune[@]}" \) -prune -o -name '*.config' -print 2>/dev/null | head -1)"
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
else
  echo "No diagnostics. ✓"
fi

[[ "$n_err" -gt 0 ]] && exit 1 || exit 0
