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

  # One scheme on both shells: green user@host, blue path, yellow git branch.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt PROMPT_SUBST 2>/dev/null || true
    # Reflect user@host:dir in the terminal title, as the bash branch does.
    # add-zsh-hook composes with other precmd users (e.g. Apple's /etc/zshrc).
    case "${TERM:-}" in
      xterm*|rxvt*)
        _dotfiles_set_title() { print -Pn '\e]0;%n@%m: %~\a'; }
        autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd _dotfiles_set_title
        ;;
    esac
    if [ "$_dotfiles_color" = 1 ]; then
      PS1='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}$(__dotfiles_git_ps1 " (%s)")%f%# '
    else
      PS1='%n@%m:%~$(__dotfiles_git_ps1 " (%s)")%# '
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    # Reflect user@host:dir in the terminal title on xterm-alikes (as stock Debian does).
    case "${TERM:-}" in
      xterm*|rxvt*) _dotfiles_title='\[\e]0;\u@\h: \w\a\]' ;;
      *) _dotfiles_title='' ;;
    esac
    if [ "$_dotfiles_color" = 1 ]; then
      PS1="${_dotfiles_title}"'\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;33m\]$(__dotfiles_git_ps1 " (%s)")\[\033[00m\]\$ '
    else
      PS1="${_dotfiles_title}"'\u@\h:\w$(__dotfiles_git_ps1 " (%s)")\$ '
    fi
    unset _dotfiles_title
  fi

  unset _dotfiles_color
fi
