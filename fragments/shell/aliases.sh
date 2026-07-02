# shellcheck shell=sh

# Colorize ls by file type — GNU ls uses --color, BSD ls (macOS) uses CLICOLOR.
if ls --version >/dev/null 2>&1; then
  alias ls='ls --color=auto'
else
  export CLICOLOR=1
  # Match GNU defaults where it shows: bold-blue dirs (Ex), bold-cyan symlinks
  # (Gx), bold-green executables (Cx). BSD's own default paints executables red.
  export LSCOLORS="ExGxcxdxCxegedabagacad"
fi

alias ll='ls -lah'
alias gs='git status --short --branch'
alias gd='git diff'
alias gl='git log --oneline --decorate --graph --all -n 30'
alias v='vim'

# Prefer nvim, fall back to vim then vi — never point $EDITOR at a missing binary.
if command -v nvim >/dev/null 2>&1; then
  alias vim='nvim'
  export EDITOR=nvim VISUAL=nvim
elif command -v vim >/dev/null 2>&1; then
  export EDITOR=vim VISUAL=vim
else
  export EDITOR=vi VISUAL=vi
fi
