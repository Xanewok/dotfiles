# dotfiles

Additive macOS + Linux dotfiles: the same shell/git/tooling on every machine, safe
to run unattended in a devcontainer, and enough to rebuild a machine from scratch.
Nothing existing is replaced, re-running is idempotent, removal is two steps. Not a
machine-management framework (no Nix, chezmoi, Ansible).

## Quick start

```sh
git clone https://github.com/Xanewok/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh            # config only: no sudo, no packages, never replaces a file
./install.sh dev        # + CLI tools (Homebrew on macOS, apt on Linux)
./install.sh desktop    # + GUI apps
./install.sh workstation
```

Profiles are cumulative (`config`, then `dev`, `desktop`, `workstation`); no argument
means `config`. `dev`/`desktop` skip package installs inside a container.

| Profile | Adds |
|---|---|
| `config` | guarded blocks + fragments copied into the namespace |
| `dev` | CLI essentials; on Linux also a pinned `mise` binary |
| `desktop` | fonts + GUI apps (macOS: Ghostty, VS Code, 1Password) |
| `workstation` | personal host policy; empty so far |

Capabilities are orthogonal, invoked by name rather than stacked in the ladder:

```sh
./install.sh mobile                   # Expo/React-Native toolchain, on top of dev
./install.sh mobile --agree-licenses  # headless: accept Android SDK licenses non-interactively
```

`mobile`: Xcode license + iOS simulator (macOS, no Apple ID), checksum-pinned Android
SDK + emulator (macOS and x86_64/arm64 Linux), CocoaPods, watchman, JDK.

Package lists are `linux/apt.*.txt` and `macos/Brewfile.*`. Edit those, not the scripts.

### Fresh macOS (no git yet)

```sh
curl -fsSL https://github.com/Xanewok/dotfiles/archive/main.tar.gz | tar xz
cd dotfiles-main && ./install.sh
```

## How it works

`config` copies `fragments/` and `resources/` into `~/.config/xanewok-dotfiles`, then
adds one guarded block to each rc file (`.zshrc`, `.bashrc`, the login files,
`.gitconfig`, tmux/vim/Neovim, Ghostty, the `mise` drop-in, and `~/.ssh/config`):

```sh
# >>> xanewok dotfiles >>>
if [ -f "$HOME/.config/xanewok-dotfiles/fragments/shell/loader.sh" ]; then
  . "$HOME/.config/xanewok-dotfiles/fragments/shell/loader.sh"
fi
# <<< xanewok dotfiles <<<
```

- The guarded block is the only edit to a real dotfile. Change the setup by editing a
  fragment and re-running; the installer rewrites only its own block, leaves a malformed
  one untouched, and skips a no-op write.
- It's sourced from login files too (`.zprofile`, the live bash login file) so a headless
  `zsh -lc` build gets the toolchain. Env loads in every shell; aliases and the prompt
  load only in interactive ones.
- `mise` supplies optional per-project toolchains (e.g. Node, Java); brew/apt supply the
  baseline. A pre-set `ANDROID_HOME` or existing toolchain manager is left alone.
- `~/.ssh/config` is the one security-sensitive target: it gets only an `Include` of a
  fragment gated to macOS's Secure Enclave key provider (inert on Linux and pre-Tahoe
  macOS). Your keys and the rest of your ssh config are never touched. Setup, assumptions,
  and gotchas: [`docs/ssh-secure-enclave.md`](docs/ssh-secure-enclave.md).
- `~/.config/xanewok-local/shell/local.sh` is an untracked per-machine overlay, sourced
  last; host quirks and machine secrets go there.

## tmux sessions that survive a reboot (opt-in, Linux)

`resources/tmux-sessions/tmux-sessions save` records every tmux pane (session, window,
dir, and the Claude Code session running in it). `restore` recreates the missing sessions,
panes tiled, and runs `claude --resume <id>` in them. Sessions named in
`~/.config/xanewok-local/tmux/sessions.conf` (`name dir` per line) always exist, at least
as one window.

Two systemd user units run it: `tmux-sessions-restore.service` at boot and
`tmux-sessions-save.timer` every 5 minutes. With linger (`loginctl enable-linger`) both run
without any login, and the tmux server and its panes get the user session env
(`XDG_RUNTIME_DIR`, the session bus), which a cron-started server lacks.

```sh
d=~/.config/xanewok-dotfiles/resources/tmux-sessions
systemctl --user enable $d/tmux-sessions-restore.service $d/tmux-sessions-save.service
systemctl --user enable --now $d/tmux-sessions-save.timer
```

Machine-specific env for the panes (e.g. `SSH_AUTH_SOCK` for a gpg-agent) goes in a drop-in:
`systemctl --user edit tmux-sessions-restore`. The user manager gains desktop variables only
after a graphical login, so do not rely on them at boot.

`./install.sh remove` disables the units. By hand (stopping them never kills the tmux server):

```sh
systemctl --user disable --now tmux-sessions-save.timer tmux-sessions-save.service tmux-sessions-restore.service
rm -r ~/.config/systemd/user/tmux-sessions-restore.service.d ~/.local/state/tmux-sessions
```

## Trust boundaries

- Homebrew's installer is offered interactively with the command shown, never run silently.
- No third-party apt repos. `mise` (Linux) and the Android cmdline-tools zip are single
  downloads pinned to a committed sha256 (`resources/*/pinned.env`); the pins document
  their trust root (download-channel integrity, not supply-chain proof).
- Xcode never signs in with an Apple ID. It's an Apple-signed `.xip` transferred from
  elsewhere.
- `mobile` prompts for the Android SDK licenses on a terminal and refuses them
  non-interactively unless you pass `--agree-licenses`. No direnv-style shell hooks.

## Uninstall

`./install.sh remove` strips the guarded blocks and deletes `~/.config/xanewok-dotfiles`.
Packages and the `~/.config/xanewok-local` overlay are left alone.

## Development

`scripts/smoke-test.sh` checks shell syntax and the guarded-block editor. Portability
floor: bash 3.2 + BSD awk (macOS defaults).
