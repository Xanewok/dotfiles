#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"
. "$DOTFILES_ROOT/scripts/guarded-block.sh"

log "installing dotfiles fragments/resources"
"$DOTFILES_ROOT/scripts/install-assets.sh"

shell_block='if [ -f "$HOME/.config/xanewok-dotfiles/fragments/shell/loader.sh" ]; then
  . "$HOME/.config/xanewok-dotfiles/fragments/shell/loader.sh"
fi'

log "adding guarded shell blocks"
ensure_guarded_block "$HOME/.zshrc" "xanewok dotfiles" "#" "$shell_block"
ensure_guarded_block "$HOME/.bashrc" "xanewok dotfiles" "#" "$shell_block"

git_block='[include]
    path = ~/.config/xanewok-dotfiles/fragments/git/config'

log "adding guarded git config include"
ensure_guarded_block "$HOME/.gitconfig" "xanewok dotfiles" "#" "$git_block"

tmux_block='source-file ~/.config/xanewok-dotfiles/fragments/tmux/tmux.conf'

log "adding guarded tmux config include"
ensure_guarded_block "$HOME/.tmux.conf" "xanewok dotfiles" "#" "$tmux_block"

vim_block='if filereadable(expand("~/.config/xanewok-dotfiles/fragments/vim/vimrc"))
  source ~/.config/xanewok-dotfiles/fragments/vim/vimrc
endif'

log "adding guarded vim + neovim config include"
ensure_guarded_block "$HOME/.vimrc" "xanewok dotfiles" '"' "$vim_block"
ensure_guarded_block "$HOME/.config/nvim/init.vim" "xanewok dotfiles" '"' "$vim_block"

# Ghostty may not be installed; the block is still additive.
if [ -f "$HOME/.config/xanewok-dotfiles/fragments/ghostty/config.ghostty" ]; then
  ghostty_block="$(cat "$HOME/.config/xanewok-dotfiles/fragments/ghostty/config.ghostty")"
  log "adding guarded Ghostty config block"
  ensure_guarded_block "$HOME/.config/ghostty/config.ghostty" "xanewok dotfiles" "#" "$ghostty_block"
fi

log "config profile complete"
