# BRIEF: Additive Dotfiles Bootstrap

## Goal

Design and implement a small dotfiles bootstrap system that can be used after a machine wipe/security incident to restore a coherent development environment on macOS and Linux, without taking ownership of the base machine configuration.

The system must be simple enough to audit and maintain. It should not become a full OS management framework.

## Core requirements

1. One public entrypoint: `./install.sh`.
2. No arguments must mean safe config-only mode.
3. Profiles must be cumulative:
   - `config`
   - `dev`
   - `desktop`
   - `workstation`
4. Dotfiles must be additive:
   - never replace `.zshrc`, `.bashrc`, `.gitconfig`, `.tmux.conf`, `.vimrc`, etc.
   - only add/update guarded blocks
5. All substantial config lives in a dotfiles-owned namespace:
   - `~/.config/xanewok-dotfiles`
6. Support fragments and resources:
   - fragments = config snippets
   - resources = helper scripts/assets consumed by fragments
7. Shell config must support PATH, aliases, and prompt setup through a single loader.
8. Package manager bootstrap must be conservative:
   - Homebrew may be offered interactively on macOS
   - apt is supported on Linux
   - no third-party apt repos automatically
9. Package installs must be skipped inside containers.
10. Risky/heavy systems are out of scope for the first implementation:
    - Docker/Podman
    - Xcode full install
    - Android SDK/emulators
    - direnv hook
    - 1Password CLI
    - local LLM stack

## Desired user experience

Fresh machine:

```sh
git clone https://github.com/Xanewok/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh config
./install.sh dev
./install.sh desktop
```

Devcontainer/Codespaces-style tooling:

```sh
./install.sh
```

must be safe and non-invasive.

## Implementation approach

### install.sh

Parses the profile and runs cumulative profile scripts.

### profiles/config.sh

- Links/copies fragments and resources into `~/.config/xanewok-dotfiles`.
- Adds guarded blocks to:
  - `~/.zshrc`
  - `~/.bashrc`
  - `~/.gitconfig`
  - `~/.tmux.conf`
  - `~/.vimrc`
  - `~/.config/ghostty/config`

### profiles/dev.sh

- Skips inside containers.
- macOS: bootstrap/check Homebrew, then `brew bundle --file macos/Brewfile.dev`.
- Linux: apt install packages from `linux/apt.dev.txt`.

### profiles/desktop.sh

- Skips/fails inside containers.
- macOS: `brew bundle --file macos/Brewfile.desktop`.
- Linux: apt install packages from `linux/apt.desktop.txt`.

### profiles/workstation.sh

- Placeholder for personal host policy.
- Should remain small until real needs appear.

## Guarded block contract

Guarded block marker format:

```txt
# >>> xanewok dotfiles >>>
...
# <<< xanewok dotfiles <<<
```

For Vim, use Vim comments:

```vim
" >>> xanewok dotfiles >>>
...
" <<< xanewok dotfiles <<<
```

Installer must update only its own marked region and leave the rest of the file unchanged.

## Non-goals

- No chezmoi dependency in v1.
- No Nix/home-manager dependency in v1.
- No Ansible.
- No secret management automation.
- No hidden shell hook enablement.
- No replacing base dotfiles with symlinks.

## Future extensions

Potential later additions:

- `./install.sh remove config` to remove guarded blocks. (Done: `./install.sh remove`.)
- Explicit capabilities such as containers, Rust, Node, mobile, local-LLM.
  Unlike profiles, capabilities are *orthogonal*, explicitly invoked groups
  (e.g. `./install.sh mobile`) — they do not stack in the config→dev→desktop
  chain; a machine opts into the roles it plays. Inclusion test for the base
  profiles vs a capability: (1) auditable in one sitting (Xcode/Android SDK
  are not), (2) no extra consent boundary (Apple ID, SDK licenses stay
  interactive, inside the capability), (3) every machine wants it vs only
  machines with that role. First real candidate: `mobile` for the Expo stack —
  Xcode as an Apple-signed `.xip` downloaded on another device and transferred
  (no Apple ID ever signs into the machine — owner policy; `xip --expand`
  verifies Apple's signature), then `xcodebuild -license accept` +
  `xcodebuild -downloadPlatform iOS` (both anonymous); Android Studio cask,
  Java via mise pins, ANDROID_HOME env fragment; SDK license acceptance stays
  a documented manual step. Simulator builds need no signing identity;
  physical-device builds go through EAS (credentials live at Expo, not here).
- Host-specific ignored local overlays.
- Chezmoi backend while preserving `install.sh` as the public contract.
- Hostname-hashed *accent* color for the prompt's host segment only (rest of the
  prompt stays as is) — glanceable which-box-am-I across the fleet. Hash with
  `cksum` (POSIX; macOS has no md5sum) into a curated readable palette, computed
  once at shell start. See https://superuser.com/questions/1123671/hash-hostname-into-a-color,
  https://aweirdimagination.net/2015/02/27/hash-based-hostname-colors/,
  https://github.com/ramnes/context-color.
