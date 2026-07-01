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

# tmux loads only the FIRST of ~/.tmux.conf and ~/.config/tmux/tmux.conf — creating
# the legacy path would shadow an existing XDG config, so target whichever is live.
tmux_target="$HOME/.tmux.conf"
if [ ! -e "$tmux_target" ] && [ -f "$HOME/.config/tmux/tmux.conf" ]; then
  tmux_target="$HOME/.config/tmux/tmux.conf"
fi

log "adding guarded tmux config include"
ensure_guarded_block "$tmux_target" "xanewok dotfiles" "#" "$tmux_block"

vim_block='if filereadable(expand("~/.config/xanewok-dotfiles/fragments/vim/vimrc"))
  source ~/.config/xanewok-dotfiles/fragments/vim/vimrc
endif'

log "adding guarded vim + neovim config include"
ensure_guarded_block "$HOME/.vimrc" "xanewok dotfiles" '"' "$vim_block"
# Neovim errors at startup (E5422) when both init.vim and init.lua exist — don't create that.
if [ -f "$HOME/.config/nvim/init.lua" ]; then
  warn "init.lua present; skipping nvim block — source the vim fragment from init.lua if wanted"
else
  ensure_guarded_block "$HOME/.config/nvim/init.vim" "xanewok dotfiles" '"' "$vim_block"
fi

# Ghostty may not be installed; the block is still additive. Ghostty only reads
# ~/.config/ghostty/config (also on macOS) — the fragment's .ghostty suffix is
# a repo naming convention, not a path Ghostty knows about.
if [ -f "$DOTFILES_ROOT/fragments/ghostty/config.ghostty" ]; then
  ghostty_block="$(cat "$DOTFILES_ROOT/fragments/ghostty/config.ghostty")"
  log "adding guarded Ghostty config block"
  ensure_guarded_block "$HOME/.config/ghostty/config" "xanewok dotfiles" "#" "$ghostty_block"
fi

log "config profile complete"
