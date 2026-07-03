# shellcheck shell=sh

# Treat `#` as a comment interactively so pasting a commented command doesn't error.
# zsh has this off by default; bash's equivalent (interactive_comments) is already on.
if [ -n "${ZSH_VERSION:-}" ]; then
  setopt INTERACTIVE_COMMENTS
fi

# Colorize ls by file type — GNU ls uses --color, BSD ls (macOS) uses CLICOLOR.
if ls --version >/dev/null 2>&1; then
  alias ls='ls --color=auto'
else
  export CLICOLOR=1
fi

alias ll='ls -lah'
alias gs='git status --short --branch'
alias gd='git diff'
alias gl='git log --oneline --decorate --graph --all -n 30'
alias v='vim'

# Debian/Ubuntu ship bat's binary as `batcat` (clash with an old `bat` package); normalize it.
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  alias bat='batcat'
fi

# Prefer nvim, fall back to vim then vi — never point $EDITOR at a missing binary.
if command -v nvim >/dev/null 2>&1; then
  alias vim='nvim'
  export EDITOR=nvim VISUAL=nvim
elif command -v vim >/dev/null 2>&1; then
  export EDITOR=vim VISUAL=vim
else
  export EDITOR=vi VISUAL=vi
fi
