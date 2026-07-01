# shellcheck shell=sh

DOTFILES_HOME="$HOME/.config/xanewok-dotfiles"

_dotfiles_source() {
  # `|| return 0`, not `&&`: an absent optional file must not leave a nonzero
  # status behind (it becomes the rc file's exit status, and breaks `set -e` sourcers).
  [ -f "$1" ] || return 0
  . "$1"
}

_dotfiles_source "$DOTFILES_HOME/fragments/shell/path.sh"
_dotfiles_source "$DOTFILES_HOME/fragments/shell/aliases.sh"
_dotfiles_source "$DOTFILES_HOME/fragments/shell/prompt.sh"

# Local, untracked per-machine extension point.
_dotfiles_source "$HOME/.config/xanewok-local/shell/local.sh"
