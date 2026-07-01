#!/usr/bin/env bash
set -euo pipefail

LAYER="${1:-dev}"

. "$DOTFILES_ROOT/scripts/lib.sh"

has brew || die "Homebrew not installed"

case "$LAYER" in
  dev)
    brew bundle --file "$DOTFILES_ROOT/macos/Brewfile.dev"
    ;;
  desktop)
    brew bundle --file "$DOTFILES_ROOT/macos/Brewfile.desktop"
    ;;
  *)
    die "unknown brew layer: $LAYER"
    ;;
esac
