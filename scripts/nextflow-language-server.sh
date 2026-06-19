#!/usr/bin/env bash
#
# Launcher for the official Nextflow language server, used by the plugin's LSP
# integration (see .lsp.json). The language server gives the agent real-time
# diagnostics, go-to-definition, and hover info for `.nf` scripts and
# `nextflow.config` files. Source: https://github.com/nextflow-io/language-server
#
# Resolution order:
#   1. `nlsp` on PATH        — the native (GraalVM) build, no JVM startup cost.
#   2. $NEXTFLOW_LSP_JAR     — a user-supplied language-server-all.jar.
#   3. cached/downloaded jar — fetched once into the plugin's persistent data dir.
#
# The server speaks LSP over stdio, so we `exec` to hand our stdio to it.

set -euo pipefail

# The language server tracks Nextflow's calendar versioning; pin to a release
# that matches the Nextflow 26.04+ baseline the other skills require.
VERSION="${NEXTFLOW_LSP_VERSION:-26.04.1}"

# 1. Prefer the native binary if the user has installed it.
if command -v nlsp >/dev/null 2>&1; then
  exec nlsp "$@"
fi

# 2./3. Otherwise run the JAR, which needs a JVM.
jar="${NEXTFLOW_LSP_JAR:-}"

if [ -z "$jar" ]; then
  # Persist the jar across plugin updates; fall back to a cache dir when the
  # plugin data dir isn't provided (e.g. running the script standalone).
  data_dir="${CLAUDE_PLUGIN_DATA:-${HOME}/.cache/nextflow-language-server}"
  jar="${data_dir}/language-server-${VERSION}-all.jar"

  if [ ! -f "$jar" ]; then
    mkdir -p "$data_dir"
    url="https://github.com/nextflow-io/language-server/releases/download/v${VERSION}/language-server-all.jar"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$url" -o "${jar}.tmp"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "${jar}.tmp" "$url"
    else
      echo "nextflow-language-server: need curl or wget to download $url" >&2
      echo "  Install one, set \$NEXTFLOW_LSP_JAR to a local language-server-all.jar," >&2
      echo "  or put a native 'nlsp' binary on PATH." >&2
      exit 1
    fi
    mv "${jar}.tmp" "$jar"
  fi
fi

if ! command -v java >/dev/null 2>&1; then
  echo "nextflow-language-server: Java 17+ is required to run the language server." >&2
  echo "  Run the install-nextflow skill, or install a native 'nlsp' binary on PATH." >&2
  exit 1
fi

exec java -jar "$jar" "$@"
