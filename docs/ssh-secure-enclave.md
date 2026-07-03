# SSH keys: native Secure Enclave (macOS Tahoe)

On macOS 26+ (Tahoe), this repo points `ssh` at a key held in the **Secure Enclave**,
gated by **Touch ID**, through Apple's built-in provider
(`/usr/lib/ssh-keychain.dylib`). No dongle, no third-party agent; the key is
hardware-bound and non-exportable.

This is the one **opinionated, manual** piece of the setup. Unlike "append my config"
or "install my packages", it makes assumptions and needs one-time per-Mac steps — read
the assumptions before relying on it.

## Installer vs. you

- **The installer** (`install.sh config`) adds a guarded `Include` to `~/.ssh/config`
  pointing at `fragments/ssh/config`, which sets `SecurityKeyProvider` **only when the
  provider file exists** (macOS Tahoe). Inert on Linux and pre-Tahoe macOS. It does
  **not** create any key.
- **You** (once per Mac) generate the enclave key and enroll its public key. Keys are
  per-device and are never stored in the repo — same as any private key.

## One-time setup (per Mac)

```sh
# 0. confirm Tahoe + the provider
sw_vers | grep ProductVersion            # 26.x
ls /usr/lib/ssh-keychain.dylib

# 1. create the enclave key (Touch ID, non-exportable)
sc_auth create-ctk-identity -l ssh -k p-256-ne -t bio
sc_auth list-ctk-identities

# 2. write the public key at the DEFAULT path so ssh auto-discovers it (no IdentityFile)
ssh-keygen -w /usr/lib/ssh-keychain.dylib -K -N ""
mv ~/.ssh/id_ecdsa_sk_rk     ~/.ssh/id_ecdsa_sk
mv ~/.ssh/id_ecdsa_sk_rk.pub ~/.ssh/id_ecdsa_sk.pub

# 3. enroll the public key (GitHub -> Settings -> SSH keys; servers' authorized_keys)
pbcopy < ~/.ssh/id_ecdsa_sk.pub

# 4. wire up + verify
cd ~/repos/dotfiles && git pull && ./install.sh config
ssh -G github.com | grep -i securitykeyprovider   # -> /usr/lib/ssh-keychain.dylib
ssh -T git@github.com                              # Touch ID; press Enter at the PIN prompt
```

## Assumptions (be careful)

- **The enclave is *the* key on this Mac.** The fragment sets `SecurityKeyProvider`
  globally (all hosts). If you *also* use a physical **FIDO `-sk` key** on the same Mac,
  this breaks it — a FIDO key needs the built-in `internal` provider, and the global
  override points ssh at Apple's dylib instead. Fix: scope the fragment to specific hosts
  (`Match host … exec …`). We don't, because on our Macs the enclave replaces that use.
- **Default key name is required.** The key must live at `~/.ssh/id_ecdsa_sk` (an ssh
  default-identity name). The fragment has no `IdentityFile` on purpose — that keeps it
  machine-agnostic — so ssh only finds the key by that default name.
- **Per-device keys.** Each Mac has its own enclave key and it cannot move to another
  machine (that's the point). Enroll **every** device's public key on each service, and
  keep **2+ keys per service** (e.g. your YubiKey) so a lost or dead Mac isn't a lockout.

## Gotchas

- **PIN prompt:** ssh asks "Enter PIN" even though the key is biometric. Press **Enter**
  (empty) — the Touch ID / "confirm user presence" step is the real gate.
- **Old default keys win.** ssh tries `~/.ssh/id_rsa` (and other defaults) *before*
  `id_ecdsa_sk`. If an old key is also enrolled on a host, it authenticates first — no
  Touch ID, enclave key never used. Retire old keys you don't want, or scope per host.
- **No attestation.** The server can't cryptographically verify the key is enclave-backed
  (it looks like a normal `sk-ecdsa` key). Fine for personal GitHub/servers; where an org
  enforces attested hardware keys, use a YubiKey instead.
- **P-256 only.** The enclave signs `sk-ecdsa-sha2-nistp256` — accepted by GitHub and
  modern servers; very old servers may reject the `sk-` key type.

## Verify / undo

- **Verify:** `ssh -G <host> | grep -i securitykeyprovider` shows the dylib, and
  `ssh -T git@github.com` prompts for Touch ID.
- **Undo the config wiring:** `./install.sh remove` strips the guarded block. The key
  itself stays in the enclave until you delete it (`sc_auth list-ctk-identities`, then
  remove via `sc_auth`).

## Optional: sign git commits with this key

git 2.34+ can sign commits over SSH with the same key:

```sh
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ecdsa_sk.pub
git config --global commit.gpgsign true
# and in your env (e.g. .zprofile) so git's `ssh-keygen -Y sign` reaches the enclave:
export SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib
```

Also add the same public key to GitHub a second time as a **Signing key** (GitHub
separates Authentication vs Signing keys) so commits show **Verified**. Note: each
signature is a separate Touch ID, so a large rebase = one touch per rewritten commit.

## Reference

Upstream guide (Apple's native path is new and lightly documented):
<https://gist.github.com/arianvp/5f59f1783e3eaf1a2d4cd8e952bb4acf>
