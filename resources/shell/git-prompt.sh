# shellcheck shell=sh
# Provide __dotfiles_git_ps1 for the prompt. Prefer git's own __git_ps1 (richer:
# dirty/stash/upstream state) when available; fall back to a minimal built-in so
# a bare machine still gets a branch name.
#
# We deliberately do NOT vendor git's git-prompt.sh: sourcing the copy the OS
# already ships means we trust apt/brew's signed package, not an unverified file
# committed to this repo — and the system copy tends to be newer than a
# hand-carried one anyway. Signed system locations are tried first; a manually
# placed ~/git-prompt.sh is only a last resort.
if ! command -v __git_ps1 >/dev/null 2>&1; then
  for _gp in \
    /usr/lib/git-core/git-sh-prompt \
    /usr/share/git-core/contrib/completion/git-prompt.sh \
    /opt/homebrew/share/git-core/contrib/completion/git-prompt.sh \
    /opt/homebrew/etc/bash_completion.d/git-prompt.sh \
    /usr/local/share/git-core/contrib/completion/git-prompt.sh \
    /usr/local/etc/bash_completion.d/git-prompt.sh \
    /Library/Developer/CommandLineTools/usr/share/git-core/git-prompt.sh \
    /Applications/Xcode.app/Contents/Developer/usr/share/git-core/git-prompt.sh \
    "$HOME/git-prompt.sh"; do
    if [ -r "$_gp" ]; then . "$_gp"; break; fi
  done
  unset _gp
fi

if command -v __git_ps1 >/dev/null 2>&1; then
  __dotfiles_git_ps1() { __git_ps1 "$@"; }
else
  # Fallback (no __git_ps1 on this machine, e.g. Apple CLT git without contrib):
  # branch + "*" for tracked changes, using only plain git. We use
  # `git status --porcelain` rather than `git diff --quiet`: the latter can be
  # fooled by the index stat-cache after a prior git command; the former is not.
  __dotfiles_git_ps1() {
    local fmt="${1:- (%s)}" branch dirty=""
    command -v git >/dev/null 2>&1 || return 0
    branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)" || return 0
    [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] && dirty="*"
    printf "$fmt" "${branch}${dirty}"
  }
fi
