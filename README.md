# Dotfiles Bootstrap

Small, **additive** dotfiles for macOS and Linux — restores a coherent shell/tooling
setup on a fresh machine without taking ownership of the box. Safe to run in a
devcontainer; explicit profiles for a real machine. Not a machine-management
framework (no Nix/chezmoi/Ansible) — small enough to audit in one sitting.

## Usage

```sh
git clone https://github.com/Xanewok/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh            # = config: no sudo, no packages, never replaces a file
./install.sh dev        # + CLI essentials (Homebrew on macOS, apt on Linux)
./install.sh desktop    # + GUI apps
./install.sh workstation
```

Profiles are cumulative; `config` is the safe default, so a bare `./install.sh` is
non-invasive (e.g. Codespaces).

| Profile | Adds | Notes |
|---|---|---|
| `config` | fragments + guarded blocks | no sudo, no packages, never replaces a file |
| `dev` | CLI tools | skipped inside containers |
| `desktop` | GUI apps | macOS: Ghostty/VS Code/1Password/font · Linux: font only |
| `workstation` | host policy | intentionally empty for now |

Package sets are `linux/apt.*.txt` and `macos/Brewfile.*` — those files are the source
of truth, not this README.

## Why it's structured this way

**Additive, never replacing.** Your `~/.bashrc`, `~/.gitconfig`, etc. are touched only by
adding one *guarded block* that sources a loader; everything real lives under
`~/.config/xanewok-dotfiles/`. Base config stays intact, the layer is reversible, and
re-running is idempotent. The block editor (`scripts/guarded-block.sh`) never guesses on
a malformed block and only rewrites a file when content actually changes — it edits your
real dotfiles, so it must not lose data.

**One loader, versioned fragments.** The guarded block is a stable one-liner
(`source loader.sh`); all config lives in tracked `fragments/`. Changing your setup means
editing a fragment, not re-touching your rc — so the block never needs to change.

**Fragments vs resources.** `fragments/` = snippets the guarded blocks source;
`resources/` = helper scripts those fragments use.

**`config` is the safe default.** No sudo, no packages, no file replacement — safe in a
devcontainer. Everything with side effects is an explicit, heavier profile.

**Conservative package bootstrap.** No third-party apt repos added automatically;
Homebrew is offered interactively, never auto-run. You approve each trust boundary
instead of the tool silently taking standing root-trust.

**`mise` is a pinned, checksummed binary — not a vendor repo.** Installed to
`~/.local/bin`: no sudo, no standing apt-repo trust. Integrity is a sha256 you pin in
`resources/mise/pinned.env` (ships disabled until filled). Works on any distro.

**The prompt reuses the OS's `__git_ps1`, not a vendored copy** — trust the signed
apt/brew package, not executable code committed here (a plain branch fallback covers a
box without it).

**Heavy/risky things are deliberately absent** (Docker, Xcode, Android SDK, direnv hook,
1Password CLI, secret managers). Add them later as explicit, risk-aware modules; leaving
them out keeps this auditable.

## Security posture

**`fragments/` and `resources/shell/` are sourced by every interactive shell — a merged
commit is code that runs on all your machines.** Protect the repo: branch protection +
required review + signed commits + account 2FA. A `gitleaks`/`git-secrets` pre-commit
hook is the real tripwire; `.gitignore` is only a backstop.

Preferences, not secrets. Never commit SSH keys, API keys, `.env`, cloud credentials,
kubeconfigs, wallet material, signing certs, or 1Password session material. Host-specific
secrets go in an ignored local overlay (`~/.config/xanewok-local/shell/local.sh`, which
the loader sources if present).

## Uninstalling

Delete the `# >>> xanewok dotfiles >>>` … `<<<` blocks from your rc files, then
`rm -rf ~/.config/xanewok-dotfiles`.
