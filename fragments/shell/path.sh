# shellcheck shell=sh

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

# mise-managed tools — static shims, not a shell hook. Each shim resolves the
# version per-directory at exec time. The prepends below win over shims, so
# explicit user installs (~/.local/bin, cargo) stay ahead.
_dotfiles_path_prepend "$HOME/.local/share/mise/shims"

# User-local tools
_dotfiles_path_prepend "$HOME/.local/bin"

# Rust/Cargo
_dotfiles_path_prepend "$HOME/.cargo/bin"

export PATH
