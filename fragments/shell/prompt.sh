# shellcheck shell=sh

DOTFILES_HOME="$HOME/.config/xanewok-dotfiles"

if [ -f "$DOTFILES_HOME/resources/shell/git-prompt.sh" ]; then
  . "$DOTFILES_HOME/resources/shell/git-prompt.sh"
fi

# Opt out per-machine by setting this before the dotfiles block loads:
#   export XANEWOK_DOTFILES_PROMPT=0
: "${XANEWOK_DOTFILES_PROMPT:=1}"

if [ "$XANEWOK_DOTFILES_PROMPT" = "1" ]; then
  # Show "*" (unstaged) / "+" (staged) after the branch. Scoped to this block so
  # opting out of our prompt leaves your own __git_ps1 usage untouched.
  GIT_PS1_SHOWDIRTYSTATE=1

  _dotfiles_color=0
  if [ -t 1 ]; then
    if command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
      _dotfiles_color=1
    else
      case "${TERM:-}" in
        *color*|xterm*|screen*|tmux*|rxvt*|alacritty|ghostty|linux) _dotfiles_color=1 ;;
      esac
    fi
  fi

  # Matches the bashrc prompt style.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt PROMPT_SUBST 2>/dev/null || true
    if [ "$_dotfiles_color" = 1 ]; then
      PS1='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}$(__dotfiles_git_ps1 " (%s)")%f%# '
    else
      PS1='%n@%m:%~$(__dotfiles_git_ps1 " (%s)")%# '
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    if [ "$_dotfiles_color" = 1 ]; then
      PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;33m\]$(__dotfiles_git_ps1 " (%s)")\[\033[00m\]\$ '
    else
      PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w$(__dotfiles_git_ps1 " (%s)")\$ '
    fi
  fi

  unset _dotfiles_color
fi
