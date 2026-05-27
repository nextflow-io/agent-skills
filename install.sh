#!/usr/bin/env bash
#
# install.sh — install the Nextflow agent skills into a SKILL.md-compatible AI coding agent.
#
# Claude Code users should use the native plugin marketplace (see README) — it
# delivers automatic updates. This script targets agents without a native install
# path: Codex CLI, Cursor, GitHub Copilot, Gemini CLI, Goose, Windsurf, OpenCode.
#
# All supported agents expect SKILL.md as-is with YAML frontmatter; no format
# conversion is performed. The destination layout is always:
#
#   <target>/<skill-name>/SKILL.md
#
# CLI shape inspired by alirezarezvani/claude-skills (MIT):
#   https://github.com/alirezarezvani/claude-skills/blob/main/scripts/install.sh
# Credit to its authors. This is a reduced single-bundle adaptation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${SCRIPT_DIR}/skills"

AGENT=""
TARGET=""
SYMLINK=0
FORCE=0
DRY_RUN=0

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''
  C_GREEN=''; C_YELLOW=''; C_RED=''
fi
ok()   { printf '%s✓%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
info() { printf '%s•%s %s\n' "$C_DIM"    "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s✗%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }

# ---- per-agent defaults ----
# Paths verified against each agent's own documentation:
#  claude    — Anthropic Claude Code docs (~/.claude/skills/, user-wide)
#  codex     — OpenAI Codex CLI docs ($CODEX_HOME/skills, default ~/.codex/skills/)
#  cursor    — cursor.com/changelog/2-4 (.cursor/skills/, currently Cursor nightly)
#  gemini    — geminicli.com/docs/cli/skills (~/.gemini/skills/ user-wide, .gemini/skills/ project)
#  copilot   — alirezarezvani/claude-skills INSTALLATION.md (.github/skills/)
#  goose     — alirezarezvani/claude-skills INSTALLATION.md (~/.config/goose/skills/)
#  opencode  — alirezarezvani/claude-skills INSTALLATION.md (.opencode/skills/)
#  windsurf  — alirezarezvani/claude-skills INSTALLATION.md (.windsurf/skills/)
SUPPORTED_AGENTS="claude codex copilot cursor gemini goose opencode windsurf"

# Resolved absolute path used for the actual install.
agent_default_path() {
  case "$1" in
    claude)   echo "$HOME/.claude/skills" ;;
    codex)    echo "${CODEX_HOME:-$HOME/.codex}/skills" ;;
    copilot)  echo "$PWD/.github/skills" ;;
    cursor)   echo "$PWD/.cursor/skills" ;;
    gemini)   echo "$HOME/.gemini/skills" ;;
    goose)    echo "${XDG_CONFIG_HOME:-$HOME/.config}/goose/skills" ;;
    opencode) echo "$PWD/.opencode/skills" ;;
    windsurf) echo "$PWD/.windsurf/skills" ;;
    *) return 1 ;;
  esac
}

# Short, conventional form used only for display in --list.
agent_display_path() {
  case "$1" in
    claude)   echo "~/.claude/skills" ;;
    codex)    echo "~/.codex/skills" ;;
    copilot)  echo "./.github/skills" ;;
    cursor)   echo "./.cursor/skills" ;;
    gemini)   echo "~/.gemini/skills" ;;
    goose)    echo "~/.config/goose/skills" ;;
    opencode) echo "./.opencode/skills" ;;
    windsurf) echo "./.windsurf/skills" ;;
  esac
}

agent_scope() {
  case "$1" in
    claude|codex|gemini|goose) echo "user-wide" ;;
    *)                         echo "project-scoped" ;;
  esac
}

post_install_hint() {
  case "$1" in
    claude)
      warn "Claude Code's native plugin marketplace is recommended for auto-updates. See README."
      ;;
    codex)
      info "Restart Codex CLI to reload skill metadata."
      ;;
    cursor)
      info "Cursor Agent Skills currently require the nightly channel (Settings → Beta → Nightly)."
      ;;
    gemini)
      info "Gemini CLI also accepts project-scoped skills under .gemini/skills/ — override with --target if needed."
      ;;
  esac
}

list_agents() {
  printf '%sSupported agents:%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-10s %-26s %s\n' "AGENT" "DEFAULT PATH" "SCOPE"
  for a in $SUPPORTED_AGENTS; do
    printf '  %-10s %-26s %s\n' "$a" "$(agent_display_path "$a")" "$(agent_scope "$a")"
  done
  echo
  echo "All agents use SKILL.md as-is; override the path with --target <dir>."
}

usage() {
  cat <<'EOF'
Usage: install.sh --agent <name> [--target <dir>] [--symlink] [--force] [--dry-run] [-h|--help]
       install.sh --list

Install Nextflow agent skills (install-nextflow, create-workflow, run-module,
launch-workflow) into the chosen agent's skills directory.

Options:
  --agent <name>   Target agent (see --list for the full set)
  --target <dir>   Override the default destination directory
  --symlink        Symlink instead of copy, so 'git pull' propagates updates
  --force          Overwrite existing skills without prompting
  --dry-run        Print what would happen without changing the filesystem
  --list           Print all supported agents and their default install paths
  -h, --help       Show this help

Notes:
  - All targets use SKILL.md as-is; no format conversion is performed.
  - For Claude Code, prefer the native plugin marketplace (auto-updates). See README.
  - Codex CLI requires a restart after install/update to reload skill metadata.
  - User-wide agents default to ~/.<agent>/skills; project-scoped agents default
    to ./.<agent>/skills (current working directory).

Examples:
  ./install.sh --list
  ./install.sh --agent codex
  ./install.sh --agent gemini --symlink
  ./install.sh --agent codex --target ~/skills-staging --force
  ./install.sh --agent cursor --dry-run

CLI shape inspired by https://github.com/alirezarezvani/claude-skills (MIT).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agent)    AGENT="${2:-}"; shift 2 ;;
    --target)   TARGET="${2:-}"; shift 2 ;;
    --symlink)  SYMLINK=1; shift ;;
    --force)    FORCE=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --list)     list_agents; exit 0 ;;
    -h|--help)  usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
  esac
done

if [ -z "$AGENT" ]; then
  err "Missing required --agent"
  usage >&2
  exit 2
fi

if [ -z "$TARGET" ]; then
  if ! TARGET="$(agent_default_path "$AGENT")"; then
    err "Unknown agent: $AGENT"
    err "Supported: $SUPPORTED_AGENTS  (run with --list for details)"
    exit 2
  fi
fi

if [ ! -d "$SKILLS_SRC" ]; then
  err "Source skills/ directory not found: $SKILLS_SRC"
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  info "Dry run — no filesystem changes."
fi

printf '%sInstalling Nextflow skills →%s %s%s%s  %s(%s)%s\n' \
  "$C_BOLD" "$C_RESET" "$C_DIM" "$TARGET" "$C_RESET" \
  "$C_DIM" "$(agent_scope "$AGENT")" "$C_RESET"

[ "$DRY_RUN" -eq 0 ] && mkdir -p "$TARGET"

installed=0
skipped=0
for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  name="$(basename "$skill_dir")"
  src="${skill_dir%/}"
  dest="$TARGET/$name"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$FORCE" -eq 0 ]; then
      if [ ! -t 0 ]; then
        warn "$name exists at $dest — not overwriting (non-interactive). Use --force."
        skipped=$((skipped + 1))
        continue
      fi
      printf '%s%s%s exists at %s. Overwrite? [y/N] ' "$C_BOLD" "$name" "$C_RESET" "$dest"
      read -r ans
      case "$ans" in
        y|Y|yes|YES) ;;
        *) warn "Skipping $name"; skipped=$((skipped + 1)); continue ;;
      esac
    fi
    [ "$DRY_RUN" -eq 0 ] && rm -rf "$dest"
  fi

  if [ "$SYMLINK" -eq 1 ]; then
    [ "$DRY_RUN" -eq 0 ] && ln -s "$src" "$dest"
    ok "Link $name → $dest"
  else
    [ "$DRY_RUN" -eq 0 ] && cp -R "$src" "$dest"
    ok "Copy $name → $dest"
  fi
  installed=$((installed + 1))
done

suffix=""
[ "$DRY_RUN" -eq 1 ] && suffix=" — dry run"
printf '\n%sDone.%s %d installed, %d skipped (agent: %s)%s\n' \
  "$C_BOLD" "$C_RESET" "$installed" "$skipped" "$AGENT" "$suffix"

post_install_hint "$AGENT"
