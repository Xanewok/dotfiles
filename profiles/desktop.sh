#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

if [ "$DOTFILES_IN_CONTAINER" = "1" ]; then
  die "desktop profile should not run inside a container"
fi

case "$DOTFILES_OS" in
  macos)
    "$DOTFILES_ROOT/scripts/bootstrap-package-manager.sh"
    "$DOTFILES_ROOT/scripts/macos-brew.sh" desktop
    ;;
  linux)
    "$DOTFILES_ROOT/scripts/linux-apt.sh" desktop
    ;;
esac

log "desktop profile complete"
