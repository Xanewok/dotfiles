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

# Login shells source login files, NOT .zshrc/.bashrc — so a headless build over SSH
# (`zsh -lc "…"`) would otherwise miss the toolchain. Put the loader there too; it's
# idempotent, so an interactive login shell sourcing both is fine. (.zprofile, not
# .zshenv: on macOS /etc/zprofile runs path_helper AFTER .zshenv and would demote our
# PATH prepends; .zprofile runs after it, so they stick.)
ensure_guarded_block "$HOME/.zprofile" "xanewok dotfiles" "#" "$shell_block"

# bash/sh read only the FIRST of these for a login shell — target whichever is live,
# and never CREATE .bash_profile (it would shadow an existing .profile).
bash_login="$HOME/.profile"
if [ -f "$HOME/.bash_profile" ]; then
  bash_login="$HOME/.bash_profile"
elif [ -f "$HOME/.bash_login" ]; then
  bash_login="$HOME/.bash_login"
fi
ensure_guarded_block "$bash_login" "xanewok dotfiles" "#" "$shell_block"

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

# Ghostty reads only ~/.config/ghostty/config (macOS too); the fragment's
# .ghostty suffix is repo naming, not a path Ghostty knows about.
if [ -f "$DOTFILES_ROOT/fragments/ghostty/config.ghostty" ]; then
  ghostty_block="$(cat "$DOTFILES_ROOT/fragments/ghostty/config.ghostty")"
  log "adding guarded Ghostty config block"
  ensure_guarded_block "$HOME/.config/ghostty/config" "xanewok dotfiles" "#" "$ghostty_block"
fi

# Fleet tool pins for mise (a conf.d drop-in merges with mise's own global
# config, so per-machine `mise use -g` never collides with this block).
if [ -f "$DOTFILES_ROOT/fragments/mise/config.toml" ]; then
  mise_block="$(cat "$DOTFILES_ROOT/fragments/mise/config.toml")"
  log "adding guarded mise config block"
  ensure_guarded_block "$HOME/.config/mise/conf.d/xanewok-dotfiles.toml" "xanewok dotfiles" "#" "$mise_block"
  # Guarantee mise's own editable global config exists: `mise use -g` writes to
  # whichever global config it finds, and if our drop-in is the only one it
  # would edit the guarded block — which the next install wipes.
  [ -e "$HOME/.config/mise/config.toml" ] || touch "$HOME/.config/mise/config.toml"
fi

log "config profile complete"
