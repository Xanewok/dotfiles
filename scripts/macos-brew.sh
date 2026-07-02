#!/usr/bin/env bash
set -euo pipefail

LAYER="${1:-dev}"

. "$DOTFILES_ROOT/scripts/lib.sh"

case "$LAYER" in dev|desktop|mobile) ;; *) die "unknown brew layer: $LAYER" ;; esac

# brew may be on disk but not on this shell's PATH (non-login ssh shells; or the
# moment after the installer runs, which can't modify this process's environment —
# interactive shells get it via fragments/shell/path.sh). Probe the standard
# prefixes before concluding it's missing.
find_brew() {
  has brew && return 0
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
  done
  return 1
}

if ! find_brew; then
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
  find_brew || die "brew not found even after install"
fi

export HOMEBREW_NO_AUTO_UPDATE=1   # skip the slow `brew update` before each bundle

# A shared Homebrew prefix is owned by the admin who installed it; a non-admin user
# (e.g. a dedicated builder) can't write it, so `brew bundle` would fail. Degrade to a
# check + warning (an admin runs the bundle once) instead of aborting the install.
prefix="$(brew --prefix 2>/dev/null || true)"
if [ -n "$prefix" ] && [ ! -w "$prefix/Cellar" ] && [ ! -w "$prefix" ]; then
  warn "Homebrew prefix $prefix is not writable by $(id -un); skipping 'brew bundle'."
  warn "An admin should run it once. Still missing from Brewfile.$LAYER:"
  brew bundle check --file "$DOTFILES_ROOT/macos/Brewfile.$LAYER" --verbose 2>&1 | sed 's/^/  /' || true
  exit 0
fi

brew bundle --file "$DOTFILES_ROOT/macos/Brewfile.$LAYER"
