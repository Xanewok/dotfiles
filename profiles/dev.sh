#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

if [ "$DOTFILES_IN_CONTAINER" = "1" ]; then
  warn "inside container; skipping dev package installs"
  exit 0
fi

case "$DOTFILES_OS" in
  macos)
    "$DOTFILES_ROOT/scripts/macos-brew.sh" dev
    ;;
  linux)
    "$DOTFILES_ROOT/scripts/linux-apt.sh" dev
    # Debian ships fd as `fdfind` (binary name clash); the package's own README
    # suggests a user-local symlink. A real binary name — scripts, fzf, and
    # editors find it too — without pulling in a Rust toolchain for cargo install.
    if has fdfind && ! has fd && [ ! -e "$HOME/.local/bin/fd" ]; then
      mkdir -p "$HOME/.local/bin"
      ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
      log "linked ~/.local/bin/fd -> fdfind"
    fi
    # mise is not in apt; installed as a pinned, checksum-verified binary (no sudo).
    "$DOTFILES_ROOT/scripts/linux-mise.sh"
    ;;
esac

log "dev profile complete"
