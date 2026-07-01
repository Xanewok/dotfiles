# shellcheck shell=sh

DOTFILES_HOME="$HOME/.config/xanewok-dotfiles"

_dotfiles_source() {
  [ -f "$1" ] && . "$1"
}

_dotfiles_source "$DOTFILES_HOME/fragments/shell/path.sh"
_dotfiles_source "$DOTFILES_HOME/fragments/shell/aliases.sh"
_dotfiles_source "$DOTFILES_HOME/fragments/shell/prompt.sh"

# Local, untracked per-machine extension point.
_dotfiles_source "$HOME/.config/xanewok-local/shell/local.sh"
