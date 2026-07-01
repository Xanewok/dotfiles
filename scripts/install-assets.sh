#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

TARGET_HOME="$HOME/.config/xanewok-dotfiles"

# Copy, don't symlink: the install must outlive the checkout (clone, run, delete).
# fragments/ and resources/ under TARGET_HOME are repo-owned and replaced wholesale;
# per-machine state belongs in ~/.config/xanewok-local, never here.
install_copy() {
  local src=$1 dst=$2

  # Earlier versions symlinked into the checkout — migrate.
  [ -L "$dst" ] && rm -f "$dst"

  if [ -e "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1; then
    echo "  ok: $dst (unchanged)"
    return 0
  fi
  rm -rf "$dst"
  cp -R "$src" "$dst"
  echo "  copied: $dst"
}

mkdir -p "$TARGET_HOME"
install_copy "$DOTFILES_ROOT/fragments" "$TARGET_HOME/fragments"
install_copy "$DOTFILES_ROOT/resources" "$TARGET_HOME/resources"
