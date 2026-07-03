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

  # Identity is shown only when informative (Starship's rule). The username appears
  # when you're not your normal local self: a different user than you logged in as
  # (logname, not a hardcoded UID — survives macOS's 501 and managed boxes), root, or
  # over SSH. The @host is added only over SSH — it answers "where", which only matters
  # remotely. Locally as yourself the prompt is just the path. Root name is always red.
  _dotfiles_root=0
  [ "$(id -u 2>/dev/null)" = 0 ] && _dotfiles_root=1
  _dotfiles_show_host=0
  [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ] && _dotfiles_show_host=1
  _dotfiles_show_user="$_dotfiles_show_host"
  [ "$_dotfiles_root" = 1 ] && _dotfiles_show_user=1
  _dotfiles_login="$(logname 2>/dev/null || true)"
  [ -n "$_dotfiles_login" ] && [ "$_dotfiles_login" != "$(id -un 2>/dev/null)" ] && _dotfiles_show_user=1
  unset _dotfiles_login

  # Per-host hue: hash the short hostname to a 256-palette color that inherits the
  # terminal theme, skipping red/green (exit status), yellow (git), blue (path).
  # Only ~4 safe hues, so collisions happen — pin one with XANEWOK_HOST_COLOR (a
  # color index) in local.sh, read at render time. A missing cksum or broken PATH
  # degrades to one fixed color rather than erroring the prompt (an empty `%` operand
  # is a syntax error, not 0). Parens: the body is a subshell, so host/sum stay scoped.
  _dotfiles_pick_host_color() (
    host="${HOSTNAME:-${HOST:-$(hostname 2>/dev/null)}}"
    sum=$( { printf %s "${host%%.*}" | cksum | cut -d' ' -f1; } 2>/dev/null )
    case "$sum" in
      ''|*[!0-9]*) echo 6 ;;
      *) case $((sum % 4)) in 0) echo 5 ;; 1) echo 6 ;; 2) echo 13 ;; 3) echo 14 ;; esac ;;
    esac
  )
  _dotfiles_host_color="$(_dotfiles_pick_host_color)"
  unset -f _dotfiles_pick_host_color

  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt PROMPT_SUBST 2>/dev/null || true
    # Reflect user@host:dir in the terminal title. add-zsh-hook composes with other
    # precmd users (e.g. Apple's /etc/zshrc).
    case "${TERM:-}" in
      xterm*|rxvt*)
        _dotfiles_set_title() { print -Pn '\e]0;%n@%m: %~\a'; }
        autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd _dotfiles_set_title
        ;;
    esac
    if [ "$_dotfiles_color" = 1 ]; then
      # root name in red (%(!..)); @host only over SSH, in its hashed hue.
      if [ "$_dotfiles_show_host" = 1 ]; then
        _dotfiles_id="%(!.%F{red}%n%f.%n)@%F{\${XANEWOK_HOST_COLOR:-$_dotfiles_host_color}}%m%f:"
      elif [ "$_dotfiles_show_user" = 1 ]; then
        _dotfiles_id="%(!.%F{red}%n%f.%n):"
      else
        _dotfiles_id=""
      fi
      # sigil green on success, red on failure (%(?..) reads the last exit status).
      PS1="$_dotfiles_id"'%F{blue}%~%f%F{yellow}$(__dotfiles_git_ps1 " (%s)")%f%(?.%F{green}.%F{red})%#%f '
    else
      if [ "$_dotfiles_show_host" = 1 ]; then _dotfiles_id='%n@%m:'
      elif [ "$_dotfiles_show_user" = 1 ]; then _dotfiles_id='%n:'
      else _dotfiles_id=''; fi
      PS1="$_dotfiles_id"'%~$(__dotfiles_git_ps1 " (%s)")%# '
    fi
    unset _dotfiles_id
  elif [ -n "${BASH_VERSION:-}" ]; then
    # bash has no exit-status prompt escape: stash $? first each prompt (re-source-safe).
    case ";${PROMPT_COMMAND-};" in
      *"__dotfiles_ec="*) ;;
      *) PROMPT_COMMAND="__dotfiles_ec=\$?${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
    esac
    case "${TERM:-}" in
      xterm*|rxvt*) _dotfiles_title='\[\e]0;\u@\h: \w\a\]' ;;
      *) _dotfiles_title='' ;;
    esac
    if [ "$_dotfiles_color" = 1 ]; then
      [ "$_dotfiles_root" = 1 ] && _dotfiles_u='\[\033[01;31m\]\u\[\033[00m\]' || _dotfiles_u='\u'
      if [ "$_dotfiles_show_host" = 1 ]; then
        _dotfiles_id="${_dotfiles_u}@\[\033[38;5;\${XANEWOK_HOST_COLOR:-$_dotfiles_host_color}m\]\h\[\033[00m\]:"
      elif [ "$_dotfiles_show_user" = 1 ]; then
        _dotfiles_id="${_dotfiles_u}:"
      else
        _dotfiles_id=""
      fi
      # sigil green on success, red on failure (reads the stashed __dotfiles_ec).
      PS1="${_dotfiles_title}${_dotfiles_id}"'\[\033[01;34m\]\w\[\033[00m\]\[\033[01;33m\]$(__dotfiles_git_ps1 " (%s)")\[\033[00m\]\[\033[$([ "${__dotfiles_ec:-0}" = 0 ] && echo 32 || echo 31)m\]\$\[\033[00m\] '
    else
      if [ "$_dotfiles_show_host" = 1 ]; then _dotfiles_id='\u@\h:'
      elif [ "$_dotfiles_show_user" = 1 ]; then _dotfiles_id='\u:'
      else _dotfiles_id=''; fi
      PS1="${_dotfiles_title}${_dotfiles_id}"'\w$(__dotfiles_git_ps1 " (%s)")\$ '
    fi
    unset _dotfiles_title _dotfiles_u _dotfiles_id
  fi

  unset _dotfiles_color _dotfiles_host_color _dotfiles_show_host _dotfiles_show_user _dotfiles_root
fi
