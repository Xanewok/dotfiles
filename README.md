# dotfiles

Additive dotfiles for macOS and Linux — the same shell/tooling setup on every
machine, safe to run in a devcontainer. Each rc file gets a single guarded block
that sources a loader; the real config is copied to
`~/.config/xanewok-dotfiles`, so the checkout doesn't need to stay around.
Nothing existing is replaced, re-running is idempotent, and removal is two steps.

Deliberately not a machine-management framework (no Nix, chezmoi, Ansible). The
use case is restoring a working environment after a machine wipe or a security
incident, from code small enough to audit in one sitting.

## Install

```sh
git clone https://github.com/Xanewok/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh            # config only: no sudo, no packages, never replaces a file
./install.sh dev        # + CLI tools (Homebrew on macOS, apt on Linux)
./install.sh desktop    # + GUI apps
./install.sh workstation
```

Profiles are cumulative; no argument means `config`, which is why a bare
`./install.sh` is safe as an automatic Codespaces/devcontainer dotfiles script.
`dev` and `desktop` refuse to install packages inside a container.

| Profile | Adds |
|---|---|
| `config` | guarded blocks + fragment symlinks |
| `dev` | CLI essentials; on Linux also a pinned `mise` binary |
| `desktop` | macOS: Ghostty, VS Code, 1Password, Fira Code. Linux: Fira Code |
| `workstation` | personal host policy — intentionally empty so far |

Capabilities are orthogonal to the profile ladder — a machine opts into the
roles it plays: `./install.sh mobile` adds the Expo/React-Native toolchain
(Xcode license + simulator with no Apple ID on the machine, CocoaPods,
watchman, Android Studio, JDK via mise) on top of whatever profile is installed.

The package lists are `linux/apt.*.txt` and `macos/Brewfile.*`; edit those, not
the scripts.

On a fresh macOS install there is no working `git` until the Xcode Command Line
Tools are installed — `/usr/bin/git` exists but is a shim that only errors (or
pops the CLT dialog). Stock `curl` and `tar` are enough to bootstrap:

```sh
curl -fsSL https://github.com/Xanewok/dotfiles/archive/main.tar.gz | tar xz
cd dotfiles-main && ./install.sh
```

Installs are copies, so the extracted directory can be deleted afterwards.

## How it works

`config` copies `fragments/` and `resources/` into `~/.config/xanewok-dotfiles`
and adds one guarded block to each of `~/.zshrc`, `~/.bashrc`, `~/.gitconfig`,
the tmux config, `~/.vimrc`, Neovim's `init.vim`, and Ghostty's config:

```sh
# >>> xanewok dotfiles >>>
if [ -f "$HOME/.config/xanewok-dotfiles/fragments/shell/loader.sh" ]; then
  . "$HOME/.config/xanewok-dotfiles/fragments/shell/loader.sh"
fi
# <<< xanewok dotfiles <<<
```

The block is stable: changing the setup means editing a fragment and re-running
`./install.sh`, so rc files are touched once and never again. `scripts/guarded-block.sh` rewrites only its own
block, leaves a malformed block untouched (warns instead of guessing), and skips
the write when nothing changed.

Existing setups are respected: if `~/.config/nvim/init.lua` exists the Neovim
block is skipped (mixing it with `init.vim` is an error), and the tmux block goes
to whichever of `~/.tmux.conf` / `~/.config/tmux/tmux.conf` is actually loaded.

- `fragments/` — the config itself: PATH, aliases, prompt, git, tmux, vim, ghostty
- `resources/` — helpers the fragments use: git-prompt lookup, the mise version pin
- `~/.config/xanewok-local/shell/local.sh` — untracked per-machine overlay,
  sourced last if present; host quirks and secrets go there, never in the repo

## Trust boundaries

A merged commit is shell code that runs on every machine — protect the repo
(required review, signed commits, 2FA) and never commit keys, tokens, or other
credentials.

- Homebrew's installer is offered interactively with the command shown; it is
  never run silently.
- No third-party apt repos. `mise` on Linux is a single binary installed to
  `~/.local/bin`, verified against the sha256 pinned in
  `resources/mise/pinned.env` (skipped with a warning until you fill it in).
- The git prompt reuses `__git_ps1` from the OS's own git package instead of
  vendoring a copy; a plain branch-name fallback covers machines without it.
- Heavy or risky tooling (Docker, Xcode, secret managers, direnv-style shell
  hooks) is intentionally absent.

## Uninstall

`./install.sh remove` strips the guarded blocks and deletes
`~/.config/xanewok-dotfiles` — undoing exactly what `config` did. Packages from
`dev`/`desktop` and the `~/.config/xanewok-local` overlay are never touched.
Manual equivalent: delete the `# >>> xanewok dotfiles >>>` … `# <<< xanewok
dotfiles <<<` blocks from your rc files, then `rm -rf ~/.config/xanewok-dotfiles`.

## Development

`scripts/smoke-test.sh` checks syntax and exercises the guarded-block editor
(append, replace, idempotency, malformed-left-untouched). The portability floor
is bash 3.2 and BSD awk — macOS defaults.
