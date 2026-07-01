#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

if [ "$DOTFILES_IN_CONTAINER" = "1" ]; then
  die "workstation profile should not run inside a container"
fi

# Intentionally minimal — add personal host policy (macOS defaults, LaunchAgents, …) here later.
log "workstation profile complete"
