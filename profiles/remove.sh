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
remove_guarded_block "$HOME/.zprofile" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.profile" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.bash_profile" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.bash_login" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.gitconfig" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.tmux.conf" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.config/tmux/tmux.conf" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.vimrc" "xanewok dotfiles" '"'
remove_guarded_block "$HOME/.config/nvim/init.vim" "xanewok dotfiles" '"'
remove_guarded_block "$HOME/.config/ghostty/config" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.ssh/config" "xanewok dotfiles" "#"
remove_guarded_block "$HOME/.config/mise/conf.d/xanewok-dotfiles.toml" "xanewok dotfiles" "#"

# Opt-in user units link into the dir removed below: disable them first, or broken links stay.
# Stopping them never kills the tmux server (KillMode=process).
if has systemctl; then
  for unit in tmux-sessions-save.timer tmux-sessions-save.service tmux-sessions-restore.service; do
    [ -L "$HOME/.config/systemd/user/$unit" ] || continue
    log "disabling $unit"
    systemctl --user disable --now "$unit" || warn "could not disable $unit"
  done
fi

log "removing ~/.config/xanewok-dotfiles"
rm -rf "$HOME/.config/xanewok-dotfiles"

log "removed. Packages from dev/desktop and ~/.config/xanewok-local are left alone."
