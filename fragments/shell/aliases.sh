# shellcheck shell=sh

alias ll='ls -lah'
alias gs='git status --short --branch'
alias gd='git diff'
alias gl='git log --oneline --decorate --graph --all -n 30'
alias v='vim'

if command -v nvim >/dev/null 2>&1; then
  alias vim='nvim'
fi
