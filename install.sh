#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-config}"

export DOTFILES_ROOT="$ROOT"

. "$ROOT/scripts/platform.sh"
. "$ROOT/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [config|dev|desktop|workstation]

Profiles are cumulative:
  config       Additive dotfiles only: fragments/resources + guarded blocks.
  dev          config + universal CLI essentials.
  desktop      dev + GUI comfort: Ghostty, fonts, VS Code, 1Password app.
  workstation  desktop + personal host policy. Currently intentionally small.

Safe default:
  ./install.sh with no args means config only.
EOF
}

case "$PROFILE" in
  -h|--help|help)
    usage
    exit 0
    ;;
  config)
    "$ROOT/profiles/config.sh"
    ;;
  dev)
    "$ROOT/profiles/config.sh"
    "$ROOT/profiles/dev.sh"
    ;;
  desktop)
    "$ROOT/profiles/config.sh"
    "$ROOT/profiles/dev.sh"
    "$ROOT/profiles/desktop.sh"
    ;;
  workstation)
    "$ROOT/profiles/config.sh"
    "$ROOT/profiles/dev.sh"
    "$ROOT/profiles/desktop.sh"
    "$ROOT/profiles/workstation.sh"
    ;;
  *)
    die "unknown profile: $PROFILE"
    ;;
esac
