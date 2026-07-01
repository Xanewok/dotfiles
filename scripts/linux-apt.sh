#!/usr/bin/env bash
set -euo pipefail

LAYER="${1:-dev}"

. "$DOTFILES_ROOT/scripts/lib.sh"

has apt-get || die "only apt-based Linux is supported in this version"
case "$LAYER" in dev|desktop) ;; *) die "unknown apt layer: $LAYER" ;; esac

sudo apt-get update
xargs -a "$DOTFILES_ROOT/linux/apt.$LAYER.txt" sudo apt-get install -y
