#!/usr/bin/env bash

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

has() {
  command -v "$1" >/dev/null 2>&1
}

# Echo the path to mise, or nothing. It may be on disk but off a non-login shell's
# PATH, so probe the standard prefixes after `command -v`. Always returns 0 so a
# `x="$(find_mise)"` assignment can't trip errexit when mise is absent.
find_mise() {
  if command -v mise >/dev/null 2>&1; then command -v mise; return 0; fi
  local m
  for m in "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
    [ -x "$m" ] && { echo "$m"; return 0; }
  done
}

confirm() {
  local prompt="${1:-Proceed?}" answer
  if [ ! -t 0 ]; then
    return 1
  fi
  printf "%s [y/N] " "$prompt"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}
