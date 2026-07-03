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
