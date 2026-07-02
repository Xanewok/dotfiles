# shellcheck shell=sh

DOTFILES_HOME="$HOME/.config/xanewok-dotfiles"

_dotfiles_source() {
  # `|| return 0`, not `&&`: an absent optional file must not leave a nonzero
  # status behind (it becomes the rc file's exit status, and breaks `set -e` sourcers).
  [ -f "$1" ] || return 0
  . "$1"
}

# Environment (PATH, mise shims, ANDROID_HOME, exports) — every shell, so login
# non-interactive builds (`ssh host 'zsh -lc "…"'`) find the toolchain, not just
# interactive terminals.
_dotfiles_source "$DOTFILES_HOME/fragments/shell/path.sh"
_dotfiles_source "$DOTFILES_HOME/fragments/shell/env.sh"

# Interactive-only. In zsh, aliases defined at startup expand inside `zsh -c "…"`
# command strings, so loading them non-interactively could silently rewrite a build
# command; and a prompt in a script is pointless.
case $- in
  *i*)
    _dotfiles_source "$DOTFILES_HOME/fragments/shell/aliases.sh"
    _dotfiles_source "$DOTFILES_HOME/fragments/shell/prompt.sh"
    ;;
esac

# Local, untracked per-machine extension point. Must be re-source-safe: an
# interactive login shell runs the loader twice (login file + rc file).
_dotfiles_source "$HOME/.config/xanewok-local/shell/local.sh"
