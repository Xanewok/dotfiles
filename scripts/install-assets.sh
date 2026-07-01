#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

TARGET_HOME="$HOME/.config/xanewok-dotfiles"

install_link() {
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return 0
  fi
  # A real file/dir here may hold local files — refuse; only a stale symlink is safe to swap.
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    die "refusing to replace non-symlink $dst — move it aside and re-run"
  fi
  rm -f "$dst"
  ln -s "$src" "$dst"
  echo "link: $dst -> $src"
}

mkdir -p "$TARGET_HOME"
install_link "$DOTFILES_ROOT/fragments" "$TARGET_HOME/fragments"
install_link "$DOTFILES_ROOT/resources" "$TARGET_HOME/resources"
