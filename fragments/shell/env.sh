# shellcheck shell=sh

# Homebrew phones usage home by default (InfluxDB); opt out. Harmless no-op on Linux.
# Note: only covers brew runs from shells that sourced this fragment.
export HOMEBREW_NO_ANALYTICS=1

# bat follows the terminal's light/dark: `auto` detects the background via OSC 11 on each
# run and picks one of the two themes below (matching the Ghostty Solarized palette).
# Needs bat >= 0.26, which we pin via mise (apt/brew ship older).
export BAT_THEME="auto"
export BAT_THEME_DARK="Solarized (dark)"
export BAT_THEME_LIGHT="Solarized (light)"

# Rootless podman serves the Docker API for docker-compose and testcontainers when there is no docker
# CLI; needs `systemctl --user enable --now podman.socket`.
if ! command -v docker >/dev/null 2>&1 && [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/podman/podman.sock" ]; then
  export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
fi
