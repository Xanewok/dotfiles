#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

# sha256_ok FILE SHA — verify FILE against expected SHA (the -c format needs two spaces).
sha256_ok() { printf '%s  %s\n' "$2" "$1" | sha256sum -c - >/dev/null 2>&1; }

# mise isn't in apt; install a pinned, checksum-verified binary into ~/.local/bin
# (no sudo, no vendor apt repo). The committed sha256 is download-channel
# integrity only (a tampered CDN response aborts) — it does NOT stop a malicious
# commit to this repo, which edits the hash too; for that, verify against mise's
# own signed SHASUMS256.txt.

PIN="$DOTFILES_ROOT/resources/mise/pinned.env"
DEST="$HOME/.local/bin/mise"

[ -f "$PIN" ] || { warn "no mise pin at resources/mise/pinned.env; skipping mise"; exit 0; }
# shellcheck disable=SC1090
. "$PIN"

case "$(uname -m)" in
  x86_64|amd64)  arch="x64";   sha="${MISE_SHA256_X64:-}" ;;
  aarch64|arm64) arch="arm64"; sha="${MISE_SHA256_ARM64:-}" ;;
  *) warn "unsupported arch $(uname -m) for mise; skipping"; exit 0 ;;
esac

if [ "${MISE_VERSION:-REPLACE_ME}" = "REPLACE_ME" ] || [ -z "$sha" ] || [ "$sha" = "REPLACE_ME" ]; then
  warn "mise pin not filled in (see resources/mise/pinned.env); skipping mise"
  exit 0
fi

if [ -x "$DEST" ] && sha256_ok "$DEST" "$sha"; then
  echo "ok: mise $MISE_VERSION already installed"
  exit 0
fi

has curl || { warn "curl required to fetch mise; skipping"; exit 0; }
has sha256sum || { warn "sha256sum required to verify mise; skipping"; exit 0; }

# Asset naming per https://github.com/jdx/mise/releases — verify when you pin.
# (Use the -musl variant below for a fully static binary if you hit glibc issues.)
url="https://github.com/jdx/mise/releases/download/${MISE_VERSION}/mise-${MISE_VERSION}-linux-${arch}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

log "downloading mise ${MISE_VERSION} (${arch})"
curl -fSL "$url" -o "$tmp"

if ! sha256_ok "$tmp" "$sha"; then
  die "mise checksum mismatch — refusing to install (expected $sha for $arch)"
fi

mkdir -p "$HOME/.local/bin"
chmod +x "$tmp"
mv "$tmp" "$DEST"
trap - EXIT
log "mise ${MISE_VERSION} installed to ${DEST}"
