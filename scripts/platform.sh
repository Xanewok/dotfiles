#!/usr/bin/env bash

case "$(uname -s)" in
  Darwin)
    export DOTFILES_OS="macos"
    ;;
  Linux)
    export DOTFILES_OS="linux"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

if [ -f /.dockerenv ] \
  || [ -n "${CODESPACES:-}" ] || [ -n "${REMOTE_CONTAINERS:-}" ] || [ -n "${DEVCONTAINER:-}" ] \
  || grep -qaE '(container|docker|podman|lxc)' /proc/1/environ 2>/dev/null; then
  export DOTFILES_IN_CONTAINER="1"
else
  export DOTFILES_IN_CONTAINER="0"
fi
