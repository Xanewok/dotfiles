#!/usr/bin/env bash
set -euo pipefail

# Capability, not a profile rung: adds the Expo/React-Native toolchain (local
# `expo run:ios` / `run:android` + a bootable sim/emulator) on top of whatever
# profile the machine runs. macOS + Linux. Pure helpers + main() so smoke-test can
# source this without executing it.

# Emulator system-image ABI for a `uname -m`. NOTE: Google ships no aarch64-Linux
# host emulator, so the arm64 branch is effectively Apple Silicon; x86_64 Linux needs
# /dev/kvm to boot.
android_abi() {
  case "$1" in
    arm64|aarch64) echo "arm64-v8a" ;;
    *)             echo "x86_64" ;;
  esac
}

# SDK location per OS — fragments/shell/path.sh must agree with this.
android_sdk_root() {
  case "$1" in
    macos) echo "$HOME/Library/Android/sdk" ;;
    *)     echo "$HOME/Android/Sdk" ;;
  esac
}

# Run sdkmanager fed `y`, returning ITS exit status, not `yes`'s SIGPIPE (which
# pipefail would surface as a spurious failure). Subshell isolates the set-toggles.
sdkmanager_run() {
  ( set +e +o pipefail; yes | "$@" >/dev/null; exit "${PIPESTATUS[1]}" )
}

# API level + build-tools. Bump deliberately (must exist in Google's repo). No
# cmake/ndk: the Android Gradle Plugin fetches the exact cmake each RN project
# declares once licenses are accepted, so pinning it here would only rot on RN bumps
# (an offline build must install cmake itself).
ANDROID_API=36
ANDROID_BUILD_TOOLS=36.0.0
ANDROID_AVD_NAME=dotfiles-avd

# License consent opt-in for headless/CI; the --agree-licenses flag also sets it.
ANDROID_AGREE_LICENSES="${ANDROID_AGREE_LICENSES:-0}"

# android_accept_licenses SM SDK [extra-license-id...]
# Accept the SDK licenses, returning 0 only on real acceptance. --agree-licenses /
# ANDROID_AGREE_LICENSES=1 blanket-accepts headless; a terminal gets sdkmanager's own
# per-license prompt (informed consent, not a yes-pipe); a non-interactive run without
# the opt-in is refused. On refusal/failure it warns with the fix and returns non-zero
# so the caller skips the SDK rather than proceed on unaccepted terms.
android_accept_licenses() {
  local sm="$1" sdk="$2"; shift 2   # remaining args: extra license ids the caller needs
  if [ "$ANDROID_AGREE_LICENSES" = "1" ]; then
    log "accepting all Android SDK licenses (--agree-licenses)"
    sdkmanager_run "$sm" --sdk_root="$sdk" --licenses || true
  elif [ -t 0 ]; then
    log "review the Android SDK licenses (sdkmanager prompts per license):"
    "$sm" --sdk_root="$sdk" --licenses || true
  fi
  # sdkmanager --licenses exits 0 even when the user DECLINES, so trust the written
  # artifacts, not the exit code. Require every license the caller's packages need —
  # most use android-sdk-license, but arm64 system images use android-sdk-arm-dbt-license.
  local lic
  for lic in android-sdk-license "$@"; do
    [ -s "$sdk/licenses/$lic" ] && continue
    warn "Android SDK licenses not accepted (need a tty, or pass --agree-licenses /"
    warn "ANDROID_AGREE_LICENSES=1); skipping Android SDK. Accept later with:"
    warn "  $sm --sdk_root=$sdk --licenses"
    return 1
  done
  return 0
}

# Ensure $sdk/cmdline-tools/latest/bin/sdkmanager exists. We fetch Google's zip into
# the SDK on both OSes (no admin, no brew cask), which every later sdkmanager/avdmanager
# resolves its root from — a brew-symlinked sdkmanager instead reports its root as the
# Homebrew prefix and can't see images under $sdk ("Package path is not valid").
ensure_cmdline_tools() {
  local sdk="$1"
  [ -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ] && return 0   # adopt an existing SDK's copy
  android_download_cmdline_tools "$sdk" || return 1
  # Caller invokes us with errexit off (left of `||`), so verify the postcondition.
  [ -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ] \
    || { warn "cmdline-tools install did not produce sdkmanager"; return 1; }
}

# Fetch Google's official cmdline-tools zip into the SDK, checksum-verified per OS.
# The zip carries no license (curl+unzip, not an sdkmanager install), so consent is
# handled once at package-install time. Same pinned-download pattern as linux-mise.sh.
android_download_cmdline_tools() {
  local sdk="$1"
  local pin="$DOTFILES_ROOT/resources/android/pinned.env"
  [ -f "$pin" ] || { warn "no android pin at resources/android/pinned.env"; return 1; }
  # shellcheck disable=SC1090
  . "$pin"

  local url sha
  case "$DOTFILES_OS" in
    macos) url="${ANDROID_CLT_MACOS_URL:-}"; sha="${ANDROID_CLT_MACOS_SHA256:-}" ;;
    *)     url="${ANDROID_CLT_LINUX_URL:-}"; sha="${ANDROID_CLT_LINUX_SHA256:-}" ;;
  esac
  [ -n "$url" ] && [ -n "$sha" ] || { warn "android pin missing for $DOTFILES_OS; skipping cmdline-tools"; return 1; }
  local shacmd                                   # coreutils sha256sum (Linux) or BSD shasum (macOS)
  if has sha256sum; then shacmd="sha256sum"
  elif has shasum; then shacmd="shasum -a 256"
  else warn "need sha256sum or shasum to verify cmdline-tools; skipping"; return 1; fi
  has curl && has unzip || { warn "curl+unzip required to fetch cmdline-tools; skipping"; return 1; }

  local tmp; tmp="$(mktemp -d)"
  log "downloading Android cmdline-tools ($DOTFILES_OS)"
  if ! curl -fSL "$url" -o "$tmp/clt.zip"; then rm -rf "$tmp"; warn "cmdline-tools download failed"; return 1; fi
  if ! printf '%s  %s\n' "$sha" "$tmp/clt.zip" | $shacmd -c - >/dev/null 2>&1; then
    rm -rf "$tmp"; die "cmdline-tools checksum mismatch — refusing to install"
  fi
  if ! unzip -q "$tmp/clt.zip" -d "$tmp"; then rm -rf "$tmp"; warn "cmdline-tools unzip failed"; return 1; fi
  mkdir -p "$sdk/cmdline-tools"
  rm -rf "$sdk/cmdline-tools/latest"      # only reached when sdkmanager is absent
  mv "$tmp/cmdline-tools" "$sdk/cmdline-tools/latest"
  rm -rf "$tmp"
}

# Provision the Android SDK (macOS + Linux); every step gated or idempotent so a
# converged machine re-runs clean. A non-zero return means "not fully provisioned"
# so main() reports honestly rather than always claiming success.
provision_android_sdk() {
  local sdk; sdk="$(android_sdk_root "$DOTFILES_OS")"
  mkdir -p "$sdk"
  export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"

  [ -d "$HOME/.local/share/mise/shims" ] && PATH="$HOME/.local/share/mise/shims:$PATH"
  has java || { warn "no JDK on PATH; skipping Android SDK (install JDK 17 first)"; return 1; }

  ensure_cmdline_tools "$sdk" || { warn "cmdline-tools unavailable; skipping Android SDK"; return 1; }

  local sm="$sdk/cmdline-tools/latest/bin/sdkmanager"
  local avd="$sdk/cmdline-tools/latest/bin/avdmanager"
  local abi; abi="$(android_abi "$(uname -m)")"

  # Licenses gate the install (and AGP's later cmake fetch); refusal already warned.
  # arm64 system images need android-sdk-arm-dbt-license on top of android-sdk-license.
  local dbt=""
  [ "$abi" = "arm64-v8a" ] && dbt="android-sdk-arm-dbt-license"
  android_accept_licenses "$sm" "$sdk" $dbt || return 1

  # sdkmanager skips already-installed packages (idempotent). Fail soft: warn + skip
  # the AVD rather than abort install.sh.
  log "installing Android SDK packages (API $ANDROID_API, $abi; multi-GB on first run)"
  "$sm" --sdk_root="$sdk" \
    "platform-tools" "emulator" \
    "platforms;android-$ANDROID_API" \
    "build-tools;$ANDROID_BUILD_TOOLS" \
    "system-images;android-$ANDROID_API;google_apis;$abi" >/dev/null \
    || { warn "Android SDK package install failed; skipping AVD"; return 1; }

  # No -d: the device catalog differs across avdmanager builds and a bad id would
  # abort after the big downloads; the default device boots. Name-anchored so
  # dotfiles-avd-old isn't a false match.
  if "$avd" list avd 2>/dev/null | grep -qE "Name: ${ANDROID_AVD_NAME}$"; then
    log "AVD $ANDROID_AVD_NAME already present"
  else
    log "creating AVD $ANDROID_AVD_NAME"
    echo no | "$avd" create avd -n "$ANDROID_AVD_NAME" \
      -k "system-images;android-$ANDROID_API;google_apis;$abi" >/dev/null \
      || warn "AVD creation failed (SDK still usable; create one manually)"
  fi
  return 0   # an AVD-only hiccup above is warned, not fatal
}

# The iOS half is macOS-only (Xcode + simulator runtime). Owner policy: Xcode never
# arrives via an Apple ID — download the .xip elsewhere (browser sign-in), transfer,
# and let its signature verify. Detect via the filesystem: under a CLT-only
# xcode-select, xcodebuild's "requires Xcode" error exits 0, so its code can't gate.
provision_ios() {
  if [ -d /Applications/Xcode.app ]; then
    if [ "$(xcode-select -p 2>/dev/null)" != "/Applications/Xcode.app/Contents/Developer" ]; then
      log "switching developer directory to Xcode.app (sudo)"
      sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer \
        || warn "xcode-select needs admin; run once as an admin"
    fi
    # Gated so a converged machine re-runs sudo-free; the || warn degrades a non-admin
    # (e.g. the headless builder) instead of aborting the whole run.
    if ! xcodebuild -license check >/dev/null 2>&1; then
      log "accepting Xcode license (sudo)"
      sudo xcodebuild -license accept || warn "Xcode license needs admin; run once as an admin"
    fi
    if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
      log "installing Xcode first-launch components (sudo)"
      sudo xcodebuild -runFirstLaunch || warn "Xcode first-launch needs admin; run once as an admin"
    fi
    if ! xcrun simctl runtime list 2>/dev/null | grep -q "iOS.*Ready"; then
      log "ensuring iOS simulator runtime (large download; no Apple ID involved)"
      xcodebuild -downloadPlatform iOS \
        || warn "iOS runtime download failed (may need admin); skipping — install it once as an admin"
    fi
  else
    warn "Xcode.app missing — download the .xip on another device, transfer, then:"
    warn "  pkgutil --check-signature <path>.xip   # MUST say 'signed Apple Software';"
    warn "                                         # xip itself no longer validates"
    warn "  mkdir -p ~/xcode-stage && cd ~/xcode-stage   # NOT ~/Downloads: TCC blocks"
    warn "  xip --expand <path>.xip && mv Xcode.app /Applications/   # headless xip there fails"
    warn "re-run './install.sh mobile' afterwards; skipping the iOS half"
  fi
}

# True if a JDK with major version >= $1 is already on the machine. Reads the `java`
# on PATH, falling back to /usr/bin/java (present even in non-login shells; on macOS
# it's a stub that errors when no JDK exists, which correctly reads as "none").
_jdk_major_ge() {
  local jbin="" line major
  if command -v java >/dev/null 2>&1; then jbin=java
  elif [ -x /usr/bin/java ]; then jbin=/usr/bin/java
  else return 1; fi
  line="$("$jbin" -version 2>&1 | head -1)"
  major="$(printf '%s\n' "$line" | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
  [ "$major" = 1 ] && major="$(printf '%s\n' "$line" | sed -n 's/.*version "1\.\([0-9][0-9]*\).*/\1/p')"
  [ -n "$major" ] || return 1
  [ "$major" -ge "$1" ] 2>/dev/null
}

# maestro (always) + a JDK for Gradle/sdkmanager. Own the default JDK ONLY when the
# machine lacks one >=17: a global mise pin would shadow a deliberate system JDK (or a
# live Java service) via the shims on PATH. --path, not -g (see config.sh's mise note).
provision_jvm_tools() {
  local mise_bin; mise_bin="$(find_mise)"
  [ -n "$mise_bin" ] || { warn "mise unavailable; skipping java + maestro"; return 0; }

  if _jdk_major_ge 17; then
    log "adequate JDK already present; leaving the machine's default java alone"
  else
    log "no JDK >=17 found; pinning java@temurin-17 for this machine (mise config.toml)"
    "$mise_bin" use --path "$HOME/.config/mise/config.toml" java@temurin-17 \
      || warn "mise java failed; install a JDK 17 manually"
  fi
  "$mise_bin" use --path "$HOME/.config/mise/config.toml" maestro \
    || warn "mise maestro failed"
}

main() {
  . "$DOTFILES_ROOT/scripts/lib.sh"

  local arg
  for arg in "$@"; do
    case "$arg" in
      --agree-licenses) ANDROID_AGREE_LICENSES=1 ;;
      *) warn "ignoring unknown argument: $arg" ;;
    esac
  done

  if [ "$DOTFILES_IN_CONTAINER" = "1" ]; then
    die "mobile capability should not run inside a container"
  fi

  # mobile layers on the dev profile (mise/JDK); it doesn't reimplement it — offer to
  # run dev on a terminal, else error.
  if [ -z "$(find_mise)" ]; then
    if confirm "The dev profile (mise/JDK) hasn't run, which mobile needs. Run it now?"; then
      "$DOTFILES_ROOT/install.sh" dev
    else
      die "mobile builds on the dev profile — run './install.sh dev' first, then re-run"
    fi
  fi

  case "$DOTFILES_OS" in
    macos)
      provision_ios
      "$DOTFILES_ROOT/scripts/macos-brew.sh" mobile
      ;;
    linux) log "iOS builds are macOS-only; provisioning the Android half on Linux" ;;
  esac

  provision_jvm_tools

  local android_rc=0
  provision_android_sdk || android_rc=$?
  if [ "$android_rc" = 0 ]; then
    log "mobile capability complete"
  else
    warn "mobile capability finished, but the Android SDK was skipped/incomplete — see warnings above"
  fi
}

# Run only when executed; the smoke test sources this for its helpers.
if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  main "$@"
fi
