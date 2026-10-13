#!/usr/bin/env bash
#
# Launcher for the official Nextflow language server, used by nextflow-typecheck.sh
# to collect diagnostics for `.nf` scripts and `nextflow.config` files.
# Source: https://github.com/nextflow-io/language-server
#
# Resolution order:
#   1. `nextflow-lsp` on PATH — a native build, no JVM needed.
#   2. a jar, cached under ~/.nextflow/lsp/<prefix>/<version>.jar or downloaded from
#      GitHub. This mirrors the Nextflow VS Code extension (fetchLanguageServer.ts):
#      resolve the latest patch of a stable version (e.g. v26.04) and reuse it if present.
#      The version tracked is $NEXTFLOW_LSP_VERSION (default 26.04).
#
# The server speaks LSP over stdio, so we `exec` to hand our stdio to it.

set -euo pipefail

log() { echo "nextflow-language-server: $*" >&2; }

# 1. Native binary, if installed.
if command -v nextflow-lsp >/dev/null 2>&1; then
  log "using nextflow-lsp on PATH."
  exec nextflow-lsp "$@"
fi

# 2. Fall back to the jar.
# Stable version to track; the latest patch release is resolved at runtime.
VERSION="${NEXTFLOW_LSP_VERSION:-26.04}"
PREFIX="v${VERSION}"
# Regex-escaped prefix for matching tag/file names like v26.04.1.
PREFIX_RE="$(printf '%s' "$PREFIX" | sed 's/\./\\./g')"

if ! command -v java >/dev/null 2>&1; then
  log "Java 17+ is required to run the language server JAR."
  log "  Run the install-nextflow skill to install it."
  exit 1
fi

# Check the major version up front: the jar requires Java 17+
# Handles both the legacy `1.8.0_292` and the modern `17.0.9` / `21` forms.
java_ver="$(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -n1 || true)"
java_major="${java_ver%%[.-]*}"
[ "$java_major" = "1" ] && java_major="$(printf '%s' "$java_ver" | cut -d. -f2)"
case "$java_major" in
  ''|*[!0-9]*) ;;  # unrecognized version string — let the JVM speak for itself
  *)
    if [ "$java_major" -lt 17 ]; then
      log "Java 17+ is required to run the language server JAR (found Java ${java_ver})."
      log "  Run the install-nextflow skill to install it."
      exit 1
    fi
    ;;
esac

cache_dir="${HOME}/.nextflow/lsp/${PREFIX}"
api="https://api.github.com/repos/nextflow-io/language-server/releases?per_page=100"

# Fetch the releases list (anonymous, or authenticated to dodge rate limits).
releases=""
if command -v curl >/dev/null 2>&1; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    releases="$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H 'Accept: application/vnd.github.v3+json' "$api" 2>/dev/null || true)"
  else
    releases="$(curl -fsSL -H 'Accept: application/vnd.github.v3+json' "$api" 2>/dev/null || true)"
  fi
  fetch() { curl -fsSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  releases="$(wget -qO- "$api" 2>/dev/null || true)"
  fetch() { wget -qO "$2" "$1"; }
else
  log "need curl or wget to fetch the language server."
  exit 1
fi

# Resolve the highest patch of this stable version from the GitHub tags.
resolved=""
if [ -n "$releases" ]; then
  best_patch="$(printf '%s' "$releases" \
    | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"\([^"]*\)"$/\1/' \
    | grep -E "^${PREFIX_RE}\.[0-9]+$" \
    | sed "s/^${PREFIX_RE}\.//" \
    | sort -n | tail -n1 || true)"
  [ -n "$best_patch" ] && resolved="${PREFIX}.${best_patch}"
fi

# Fall back to the newest jar already cached if GitHub is unreachable.
if [ -z "$resolved" ] && [ -d "$cache_dir" ]; then
  resolved="$(ls "$cache_dir" 2>/dev/null \
    | grep -E "^${PREFIX_RE}\.[0-9]+\.jar$" \
    | sed 's/\.jar$//' \
    | sort -t. -k3 -n | tail -n1 || true)"
  [ -n "$resolved" ] && log "GitHub unreachable; falling back to cache."
fi

if [ -z "$resolved" ]; then
  log "could not resolve a ${PREFIX} language server release from GitHub or cache."
  exit 1
fi

jar="${cache_dir}/${resolved}.jar"

# Download once; reuse the cached jar on subsequent starts (stable releases).
if [ ! -f "$jar" ]; then
  mkdir -p "$cache_dir"
  url="https://github.com/nextflow-io/language-server/releases/download/${resolved}/language-server-all.jar"
  fetch "$url" "${jar}.tmp"
  mv "${jar}.tmp" "$jar"
  log "downloaded ${resolved}."
else
  log "using cached ${resolved}."
fi

exec java -jar "$jar" "$@"
