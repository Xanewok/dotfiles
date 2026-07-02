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
    # Debian renames fd to fdfind (name clash); its own README suggests this
    # symlink. A real binary, not an alias: fzf/editors/scripts find it too.
    if has fdfind && ! has fd && [ ! -e "$HOME/.local/bin/fd" ]; then
      mkdir -p "$HOME/.local/bin"
      ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
      log "linked ~/.local/bin/fd -> fdfind"
    fi
    # mise is not in apt; installed as a pinned, checksum-verified binary (no sudo).
    "$DOTFILES_ROOT/scripts/linux-mise.sh"
    ;;
esac

# Materialize the fleet tool pins (fragments/mise/config.toml).
mise_bin="$(command -v mise 2>/dev/null || true)"
if [ -z "$mise_bin" ]; then
  for m in "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
    if [ -x "$m" ]; then mise_bin="$m"; break; fi
  done
fi
if [ -n "$mise_bin" ]; then
  log "installing mise-pinned tools"
  # -C /: resolve config from / so only the global pins are in scope. In $HOME
  # context a stray .node-version would get installed and shimmed too — hijacking
  # node from whatever currently manages it (e.g. nodenv).
  "$mise_bin" install -C / || warn "mise install failed; pinned tools not materialized"
else
  warn "mise unavailable; skipping pinned tools"
fi

log "dev profile complete"
