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
  ./install.sh [config|dev|desktop|workstation|remove]

Profiles are cumulative:
  config       Additive dotfiles only: fragments/resources + guarded blocks.
  dev          config + universal CLI essentials.
  desktop      dev + GUI comfort: Ghostty, fonts, VS Code, 1Password app.
  workstation  desktop + personal host policy. Currently intentionally small.

  remove       Undo config: strip guarded blocks, delete ~/.config/xanewok-dotfiles.
               Packages installed by dev/desktop are never uninstalled.

Capabilities are orthogonal — run on top of whatever profile the machine has:
  mobile       Expo/React-Native toolchain; builds on the dev profile. iOS half is
               macOS-only (Xcode license + simulator, no Apple ID); Android SDK on
               macOS + Linux (emulator bootable on Apple Silicon + x86_64 Linux);
               plus Android Studio, CocoaPods, watchman. SDK licenses are prompted on
               a terminal, refused non-interactively; pass --agree-licenses for headless.

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
  remove)
    "$ROOT/profiles/remove.sh"
    ;;
  mobile)
    "$ROOT/profiles/mobile.sh" "${@:2}"
    ;;
  *)
    die "unknown profile: $PROFILE"
    ;;
esac
