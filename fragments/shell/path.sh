# shellcheck shell=sh

# Prepend $1 to PATH if it's a dir and not already present. Skip-if-present keeps
# re-sourcing (login + interactive both load the loader) dup-free.
_dotfiles_path_prepend() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

# Apple Silicon Homebrew
_dotfiles_path_prepend /opt/homebrew/bin
_dotfiles_path_prepend /opt/homebrew/sbin

# Intel macOS / common local prefix
_dotfiles_path_prepend /usr/local/bin
_dotfiles_path_prepend /usr/local/sbin

# mise-managed tools — static shims, not a shell hook: each shim resolves the
# per-directory version at exec time (no cd hook, no auto-loaded env).
_dotfiles_path_prepend "$HOME/.local/share/mise/shims"

# User-local tools
_dotfiles_path_prepend "$HOME/.local/bin"

# Rust/Cargo
_dotfiles_path_prepend "$HOME/.cargo/bin"

# Android SDK (mobile capability). Respect a user-set ANDROID_HOME (custom SDK);
# otherwise discover Studio's default location per OS.
if [ -z "${ANDROID_HOME:-}" ]; then
  for _sdk in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$_sdk" ] && { ANDROID_HOME="$_sdk"; export ANDROID_HOME; break; }
  done
  unset _sdk
fi
if [ -n "${ANDROID_HOME:-}" ]; then
  _dotfiles_path_prepend "$ANDROID_HOME/platform-tools"
  _dotfiles_path_prepend "$ANDROID_HOME/emulator"
  _dotfiles_path_prepend "$ANDROID_HOME/cmdline-tools/latest/bin"
fi

export PATH
