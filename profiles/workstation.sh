#!/usr/bin/env bash
set -euo pipefail

. "$DOTFILES_ROOT/scripts/lib.sh"

if [ "$DOTFILES_IN_CONTAINER" = "1" ]; then
  die "workstation profile should not run inside a container"
fi

cat <<'EOF'
workstation profile is intentionally minimal for now.

This is where personal host policy can later go, for example:
  - macOS defaults
  - LaunchAgents
  - backup helpers
  - security checks
  - keyboard/repeat preferences

Do not add heavy/risky subsystems here casually.
EOF

log "workstation profile complete"
