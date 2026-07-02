#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"
. "$DOTFILES_ROOT/scripts/guarded-block.sh"

# Undo exactly what the config profile did: guarded blocks + the namespace dir.
# Packages installed by dev/desktop were explicit trust decisions — never
# uninstalled here. The local overlay (~/.config/xanewok-local) is not ours to touch.

log "removing guarded blocks"
remove_guarded_block "$HOME/.zshrc" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.bashrc" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.gitconfig" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.tmux.conf" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.config/tmux/tmux.conf" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.vimrc" "xanewok dotfiles" '"'
remove_guarded_block "$HOME/.config/nvim/init.vim" "xanewok dotfiles" '"'
remove_guarded_block "$HOME/.config/ghostty/config" "xanewok dotfiles" "#"

log "removing ~/.config/xanewok-dotfiles"
rm -rf "$HOME/.config/xanewok-dotfiles"

log "removed. Packages from dev/desktop and ~/.config/xanewok-local are left alone."
