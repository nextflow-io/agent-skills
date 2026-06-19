#!/usr/bin/env bash
#
# Launcher for the official Nextflow language server, used by the plugin's LSP
# integration (see .lsp.json). It gives the agent real-time diagnostics,
# go-to-definition, and hover info for `.nf` scripts and `nextflow.config` files.
# Source: https://github.com/nextflow-io/language-server
#
# JAR management mirrors the Nextflow VS Code extension (fetchLanguageServer.ts):
# resolve the latest patch release of a minor version (e.g. v26.04) from GitHub,
# cache it under ~/.nextflow/lsp/<prefix>/<version>.jar, and reuse it if present.
#
# Resolution order:
#   1. `nlsp` on PATH        — native (GraalVM) build, no JVM startup cost.
#   2. $NEXTFLOW_LSP_JAR     — an explicit jar (e.g. a local development build).
#   3. cached/downloaded jar — latest patch of $NEXTFLOW_LSP_VERSION (default 26.04).
#
# The server speaks LSP over stdio, so we `exec` to hand our stdio to it.

set -euo pipefail

# Minor version to track; the latest patch release is resolved at runtime.
MINOR="${NEXTFLOW_LSP_VERSION:-26.04}"
PREFIX="v${MINOR}"
# Regex-escaped prefix for matching tag/file names like v26.04.1.
PREFIX_RE="$(printf '%s' "$PREFIX" | sed 's/\./\\./g')"

log() { echo "nextflow-language-server: $*" >&2; }

# 1. Prefer the native binary if installed.
if command -v nlsp >/dev/null 2>&1; then
  exec nlsp "$@"
fi

# 2. Explicit jar override (development build, custom location).
jar="${NEXTFLOW_LSP_JAR:-}"

if [ -z "$jar" ]; then
  if ! command -v java >/dev/null 2>&1; then
    log "Java 17+ is required to run the language server JAR."
    log "  Run the install-nextflow skill, or put a native 'nlsp' binary on PATH."
    exit 1
  fi

  cache_dir="${HOME}/.nextflow/lsp/${PREFIX}"
  api="https://api.github.com/repos/nextflow-io/language-server/releases"

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

  # Resolve the highest stable patch of this minor version from the GitHub tags.
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
    [ -n "$resolved" ] && log "GitHub unreachable; using cached ${resolved}."
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
  fi
fi

exec java -jar "$jar" "$@"
