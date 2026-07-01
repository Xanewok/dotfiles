#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

if [ "$DOTFILES_IN_CONTAINER" = "1" ]; then
  warn "inside container; skipping dev package installs"
  exit 0
fi

case "$DOTFILES_OS" in
  macos)
    "$DOTFILES_ROOT/scripts/bootstrap-package-manager.sh"
    "$DOTFILES_ROOT/scripts/macos-brew.sh" dev
    ;;
  linux)
    "$DOTFILES_ROOT/scripts/linux-apt.sh" dev
    # mise is not in apt; installed as a pinned, checksum-verified binary (no sudo).
    "$DOTFILES_ROOT/scripts/linux-mise.sh"
    ;;
esac

log "dev profile complete"
