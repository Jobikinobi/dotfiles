# Age identity — recovery procedure

The chezmoi age identity at `~/.config/chezmoi/key.txt` is the single critical
secret guarding everything encrypted in this dotfiles repo:

- SSH private keys (`encrypted_private_id_ed25519_pve*.age`,
  `encrypted_private_id_ed25519_macstudio.age`)
- Infra docs (`encrypted_README.md.age`, `encrypted_proxmox.md.age`)
- Anything added later with `chezmoi add --encrypt`

The matching **public recipient** is in `~/.config/chezmoi/chezmoi.toml`:

```
age1l2n5sqj8eg0728vlj6che0vas474svdxej2ceypr6046z5ylwqusr00mzj
```

The recipient is safe to share. The identity is not.

## Storing backups

The recommended posture is **at least two** independent channels with diverse
failure modes:

1. **1Password vault** (primary, cloud-syncs across devices)
2. **iCloud Keychain entry** (Apple-native, syncs to all your Apple devices)
3. **Printed paper backup** (QR + text on one sheet, filed offline)
4. **Encrypted USB drive** stored physically separate from your Mac

Pick two minimum; three or four if paranoid.

### 1Password (primary recommendation)

```bash
op signin
op document create ~/.config/chezmoi/key.txt \
   --title "chezmoi age identity" \
   --vault Private \
   --tags "chezmoi,age,recovery"

# verify
op document get "chezmoi age identity" | head -1
# should print: # created: YYYY-MM-DDTHH:MM:SS-NN:NN
```

### Paper backup

Use `qrencode` to print a scannable QR alongside the plain text:

```bash
qrencode -t PNG -o /tmp/age.qr.png -r ~/.config/chezmoi/key.txt
# print /tmp/age.qr.png and the cat output of key.txt on one sheet
# then: shred /tmp/age.qr.png
```

QR code restores via any phone QR reader → paste contents into a fresh
`~/.config/chezmoi/key.txt`.

### Encrypted USB

```bash
hdiutil create -size 100m -fs APFS -encryption AES-256 -stdinpass \
   -volname "chezmoi-recovery" ~/Documents/chezmoi-recovery.dmg
# mount, copy in the key.txt, eject, move .dmg to a physical USB stick.
```

## Restore drill

To verify your backup actually works, do this after creating each backup:

```bash
# stash the working identity
mv ~/.config/chezmoi/key.txt /tmp/key.txt.real

# restore from your backup channel into the standard location
# (e.g., op document get "chezmoi age identity" > ~/.config/chezmoi/key.txt)
mkdir -p ~/.config/chezmoi
$EDITOR ~/.config/chezmoi/key.txt    # paste the backup content
chmod 600 ~/.config/chezmoi/key.txt

# decrypt something to prove it works
chezmoi cat ~/.ssh/id_ed25519_pve | head -1
# expect: -----BEGIN OPENSSH PRIVATE KEY-----

# restore the original
mv /tmp/key.txt.real ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
```

If the `chezmoi cat` line prints the OpenSSH header, the backup is verified.

## Bootstrap a new machine

```bash
# 1. Prerequisites
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install age chezmoi

# 2. Restore the age identity from your backup BEFORE running chezmoi init.
#    Without it, chezmoi cannot decrypt anything in the repo.
mkdir -p ~/.config/chezmoi
$EDITOR ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# 3. Pull and apply
chezmoi init Jobikinobi --apply

# 4. Smoke test — both of these depend on a key this repo decrypts, so a
#    success here proves the restored age identity actually works.
ssh pve uptime
ssh macstudio uptime

# NOT a valid smoke test: `ssh portainer`. id_ed25519_portainer is a
# pre-existing local key, not one of the encrypted_private_*.age files, so it
# will be absent on a fresh machine no matter how well the identity restored.
```

## Rotation (if you suspect the identity has leaked)

```bash
# 1. Generate a new keypair
age-keygen -o ~/.config/chezmoi/key.txt.new
NEW_PUB=$(age-keygen -y ~/.config/chezmoi/key.txt.new)

# 2. Update chezmoi config with the new recipient
$EDITOR ~/.config/chezmoi/chezmoi.toml
# change the recipient line:  recipient = "$NEW_PUB"

# 3. Re-add every encrypted file (chezmoi will re-encrypt with the new recipient)
find ~/.local/share/chezmoi -name "encrypted_*.age" -exec basename {} \; |
  while read f; do
    # derive the original path; this is a pain, hand-edit if needed
    chezmoi re-add ...
  done

# 4. Replace identity
mv ~/.config/chezmoi/key.txt ~/.config/chezmoi/key.txt.old
mv ~/.config/chezmoi/key.txt.new ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# 5. Commit and push
cd ~/.local/share/chezmoi && git add -A && \
  git commit -m "rotate: chezmoi age identity" && git push

# 6. Re-distribute the new identity to your backup channels (1Password etc.)
# 7. Destroy old identity copies everywhere
```

## When the staging folder exists

If you find `~/Documents/__RECOVERY__/` lying around, that means a previous
setup phase staged the identity for transfer. Once durable backups are in
place and the drill above passes, securely delete it:

```bash
rm -rf ~/Documents/__RECOVERY__
# or:  srm -rfv ~/Documents/__RECOVERY__  (if srm is installed)
```

The folder living in `~/Documents` is intentional friction so you don't forget
about it.
