#!/usr/bin/env bash
set -euo pipefail

LAYER="${1:-dev}"

. "$DOTFILES_ROOT/scripts/lib.sh"

case "$LAYER" in dev|desktop) ;; *) die "unknown brew layer: $LAYER" ;; esac

if ! has brew; then
  cat <<'EOF'
Homebrew is not installed. Official installer (crosses a trust boundary — run only
on a clean machine you trust):
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
EOF
  if confirm "Run the official Homebrew installer now?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    die "Homebrew is required for the macOS dev/desktop profiles"
  fi
fi

export HOMEBREW_NO_AUTO_UPDATE=1   # skip the slow `brew update` before each bundle
brew bundle --file "$DOTFILES_ROOT/macos/Brewfile.$LAYER"
