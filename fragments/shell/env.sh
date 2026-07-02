# shellcheck shell=sh

# Homebrew phones usage home by default (InfluxDB); opt out. Harmless no-op on Linux.
# Note: only covers brew runs from shells that sourced this fragment.
export HOMEBREW_NO_ANALYTICS=1
