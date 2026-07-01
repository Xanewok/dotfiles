#!/usr/bin/env bash
set -euo pipefail

LAYER="${1:-dev}"

. "$DOTFILES_ROOT/scripts/lib.sh"

has apt-get || die "only apt-based Linux is supported in this version"

case "$LAYER" in
  dev)
    sudo apt-get update
    xargs -a "$DOTFILES_ROOT/linux/apt.dev.txt" sudo apt-get install -y
    ;;
  desktop)
    sudo apt-get update
    xargs -a "$DOTFILES_ROOT/linux/apt.desktop.txt" sudo apt-get install -y
    ;;
  *)
    die "unknown apt layer: $LAYER"
    ;;
esac
