# shellcheck shell=sh

# Homebrew phones usage home by default (InfluxDB); opt out. Harmless no-op on Linux.
# Note: only covers brew runs from shells that sourced this fragment.
export HOMEBREW_NO_ANALYTICS=1

# Solarized syntax highlighting for bat, to match the Ghostty Solarized theme. Fixed
# dark rather than auto: bat's light/dark auto-detect needs 0.25+, which some apt bats
# lack, so a fixed theme stays robust across versions.
export BAT_THEME="Solarized (dark)"
