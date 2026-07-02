#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

# Capability, not a profile rung: adds the Expo/React-Native toolchain on top of
# whatever profile this machine already runs. Goal: local `expo run:ios` builds.

if [ "$DOTFILES_IN_CONTAINER" = "1" ]; then
  die "mobile capability should not run inside a container"
fi

case "$DOTFILES_OS" in
  macos)
    # Xcode never arrives via an Apple ID on this machine (owner policy): download
    # the .xip elsewhere (browser-only sign-in), transfer, `xip --expand` verifies
    # Apple's signature. Detect via the filesystem — under a CLT-only xcode-select,
    # xcodebuild's "requires Xcode" error exits 0, so its exit code can't gate this.
    if [ -d /Applications/Xcode.app ]; then
      if [ "$(xcode-select -p 2>/dev/null)" != "/Applications/Xcode.app/Contents/Developer" ]; then
        log "switching developer directory to Xcode.app (sudo)"
        sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
      fi
      log "accepting Xcode license + first-launch components (sudo)"
      sudo xcodebuild -license accept
      sudo xcodebuild -runFirstLaunch
      log "ensuring iOS simulator runtime (large download; no Apple ID involved)"
      xcodebuild -downloadPlatform iOS
    else
      warn "Xcode.app missing — download the .xip on another device, transfer, then:"
      warn "  mkdir -p ~/xcode-stage && cd ~/xcode-stage   # NOT ~/Downloads: TCC blocks"
      warn "  xip --expand <path>.xip && mv Xcode.app /Applications/   # headless xip there fails"
      warn "re-run './install.sh mobile' afterwards; skipping the iOS half"
    fi
    "$DOTFILES_ROOT/scripts/macos-brew.sh" mobile
    ;;
  linux)
    # Android Studio isn't in apt; Linux boxes keep their manual setups for now.
    warn "mobile is macOS-first; on Linux only the java pin below is applied"
    ;;
esac

# Gradle needs a JDK, pinned per-machine, not in the fleet mise config — the
# machine opts into the role; other machines never download a JDK. --path, not
# -g: with only our conf.d drop-in present, -g edits (and the next install
# wipes) the guarded block.
mise_bin="$(command -v mise 2>/dev/null || true)"
if [ -z "$mise_bin" ]; then
  for m in "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
    if [ -x "$m" ]; then mise_bin="$m"; break; fi
  done
fi
if [ -n "$mise_bin" ]; then
  log "pinning java for this machine (mise config.toml)"
  "$mise_bin" use --path "$HOME/.config/mise/config.toml" java@temurin-17 \
    || warn "mise java failed; install a JDK 17 manually"
else
  warn "mise unavailable; skipping java"
fi

log "mobile capability complete"
