#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

case "$DOTFILES_OS" in
  macos)
    if has brew; then
      echo "ok: Homebrew installed"
      exit 0
    fi

    cat <<'EOF'
Homebrew is not installed.

Official install command:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

This is a package-manager bootstrap step and crosses a trust boundary.
Run only on a clean machine where you are comfortable installing Homebrew.
EOF

    if confirm "Run the official Homebrew installer now?"; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
      die "Homebrew is required for the macOS dev/desktop profiles"
    fi
    ;;

  linux)
    echo "Linux package manager bootstrap is manual in this version."
    echo "apt-get is expected for dev/desktop package installation."
    ;;
esac
