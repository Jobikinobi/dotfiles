# dotfiles — jth Mac Environment

Personal Mac environment as code. One command restores everything on a fresh macOS install.

> **Important**: The chezmoi source directory is `~/dotfiles`. Do not clone this repo anywhere else on this machine — chezmoi only reads from that path, and a second clone will drift out of sync.

---

## Quick Start (Fresh Mac)

Open Terminal and run these two commands:

```zsh
# 1. Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Restore everything
brew install chezmoi && chezmoi init --apply Jobikinobi
```

Or if you've already restored once and have the aliases loaded:

```zsh
install-brew    # installs Homebrew
mac-restore     # pulls repo + restores full environment
```

---

## What Gets Restored

| Component | Tool | Source file |
|---|---|---|
| CLI tools, GUI apps, VS Code extensions | Homebrew Bundle | `dot_Brewfile` |
| Shell config (zsh, aliases, PATH) | chezmoi | `dot_zshrc` |
| Git identity and config | chezmoi | `dot_gitconfig` |
| Terminal themes (p10k) | chezmoi | `dot_p10k.zsh` |
| Fish shell config | chezmoi | `dot_config/fish/` |
| Editor configs (helix, kitty, btop, htop) | chezmoi | `dot_config/*/` |
| GitHub CLI config | chezmoi | `dot_config/gh/` |
| SSH config (public only) | chezmoi | `private_dot_ssh/` |
| SSH keys | **manual step** — see below | — |
| AWS credentials | Doppler — see below | — |
| Daily auto-save agent | launchd (run_once) | `com.jth.mac-save.plist` |

---

## Daily Aliases

These are all defined in `.zshrc` and available after restore.

### Mac Setup

```zsh
install-brew    # install Homebrew on a fresh Mac
mac-restore     # full restore from this repo on a new Mac
mac-save        # snapshot current state → commit → push to GitHub
mac-check       # show what has drifted from saved Brewfile
```

### AWS

```zsh
aws-login       # configure AWS credentials via Doppler (master project, prd config)
aws-sso         # SSO login using hole-admin profile (AdministratorAccess, 12hr session)
aws-who         # confirm which AWS account/user is active
```

### S3 Backups

```zsh
s3-ls-mipds     # list MIPDS backup in S3 Deep Archive
s3-ls-scratch   # list mipds-scratch backup in S3 Deep Archive
```

---

## Auto-Save (Daily at 9am)

A launchd agent runs `mac-save` every morning at 9am silently in the background.
Installed automatically by chezmoi on first apply (`run_once_after_install-launchagent.sh.tmpl`).

```zsh
# Check it's running
launchctl list | grep mac-save

# Run it right now
launchctl start com.jth.mac-save

# View last run output
cat /tmp/mac-save.log
cat /tmp/mac-save.error.log

# Disable it
launchctl unload ~/Library/LaunchAgents/com.jth.mac-save.plist
```

---

## AWS Setup

### Access Keys (default profile)

Credentials live in Doppler — never stored locally.

```zsh
aws-login
# pulls AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY from Doppler master/prd
# sets region: us-east-1, output: json
```

### SSO Profiles

Two profiles are configured in `~/.aws/config`:

| Profile | Role | Session |
|---|---|---|
| `hole-admin` | AdministratorAccess | 12hr |
| `hole-bedrock` | cli-bedrock-access | 12hr |

SSO session name: `hole-sso`
Account: `420073135340` (theholetruth)

```zsh
aws-sso                                    # login via browser (hole-admin)
aws s3 ls --profile hole-admin             # use a specific profile
aws sso login --profile hole-bedrock       # login for bedrock profile
```

### Doppler Projects

| Project | Contents |
|---|---|
| `master` | AWS keys, root credentials |
| `backend` | Backend service secrets, AWS SSO URL |
| `mcp-servers` | MCP server API keys |
| `github-workflows` | GitHub Actions secrets |
| `frontend-web-design` | Frontend environment variables |

---

## S3 Backups

Bucket: `hole-foia-deep-archive`
Storage class: Glacier Deep Archive ($0.00099/GB/month)

| Folder | Contents | Size |
|---|---|---|
| `MIPDS/` | Original MIPDS drive backup | ~347 GB |
| `mipds-scratch/` | MIPDS-Scratch selected folders | growing |

```zsh
# Check MIPDS backup size
s3-ls-mipds

# Add a new folder to mipds-scratch backup
aws s3 sync "/Volumes/MIPDS-Scrattch/FolderName" \
  "s3://hole-foia-deep-archive/mipds-scratch/FolderName" \
  --storage-class DEEP_ARCHIVE \
  --only-show-errors &
```

> **Note:** The `hole-foia-deep-archive` bucket has a lifecycle rule that immediately
> transitions all uploaded objects to DEEP_ARCHIVE. Files cannot be downloaded
> instantly — retrieval takes 12–48 hours and incurs a fee. This is archive-only storage.

---

## SSH Keys

SSH private keys are **not committed to this repo** (gitignored for security).

After restore, copy them manually:

```zsh
cp -r /path/to/your/backup/.ssh ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/id_*.pub
```

Or restore from a secure location.

---

## Secrets (age encryption)

Secrets committed to this repo are encrypted with [age](https://age-encryption.org). The private key lives at `~/.config/chezmoi/key.txt` and is **never committed**.

### Add a new encrypted secret

```zsh
chezmoi add --encrypt ~/.config/some/secret-file
```

Chezmoi stores it as `encrypted_secret-file.age` (ASCII-armored, safe to push publicly). On `chezmoi apply`, it decrypts automatically.

### Edit an encrypted file

```zsh
chezmoi edit ~/.config/some/secret-file
```

Decrypts in-place in your editor, re-encrypts on save.

### Bootstrap a new machine

1. Install age: `brew install age`
2. Copy `~/.config/chezmoi/key.txt` from an existing machine via a secure channel (USB, `scp` over Tailscale, etc.). Never commit or email it.
3. `chmod 600 ~/.config/chezmoi/key.txt`
4. Run `chezmoi init --apply Jobikinobi` — encrypted files decrypt using the key

If you lose the key, encrypted files in the repo are unrecoverable. Back it up somewhere safe.

---

## Known Issues & Notes

### Apple Container Sparse Files
`~/Library/Application Support/com.apple.container` stores virtual disk images
pre-allocated to 512 GB each. On APFS they appear as ~2 GB, but any backup tool
that copies to a non-APFS destination will expand them to their full allocated size
(3.5+ TB of mostly empty space). **This folder is excluded from backups.**

### CCC Backup of Mac Studio
After deleting `com.apple.container` from the source, a fresh CCC backup should
produce ~600–650 GB (the actual data size of the machine).

### Glacier Vault (empty)
A Glacier vault named `MIPDS-Distaster-Recovery-Backup` exists in us-east-1
but is **empty** — the old Glacier API is no longer accepting operations for
this account. $0/month. No action needed.

---

## Repo Structure (chezmoi)

```
dotfiles/                                  # chezmoi source directory
├── README.md
├── .chezmoiignore                         # files chezmoi skips
├── dot_zshrc                              # → ~/.zshrc
├── dot_zshenv                             # → ~/.zshenv
├── dot_zprofile                           # → ~/.zprofile
├── dot_bash_profile                       # → ~/.bash_profile
├── dot_bashrc                             # → ~/.bashrc
├── dot_gitconfig                          # → ~/.gitconfig
├── dot_p10k.zsh                           # → ~/.p10k.zsh
├── dot_profile                            # → ~/.profile
├── dot_viminfo                            # → ~/.viminfo
├── dot_Brewfile                           # → ~/.Brewfile (Homebrew packages)
├── dot_config/
│   ├── btop/                              # → ~/.config/btop/
│   ├── fish/                              # → ~/.config/fish/
│   ├── gh/                                # → ~/.config/gh/
│   ├── helix/                             # → ~/.config/helix/
│   ├── htop/                              # → ~/.config/htop/
│   └── kitty/                             # → ~/.config/kitty/
├── private_dot_ssh/
│   └── config                             # → ~/.ssh/config
├── run_once_before_install-packages.sh.tmpl   # installs Homebrew + Brewfile
├── run_once_after_install-launchagent.sh.tmpl # installs daily auto-save agent
├── com.jth.mac-save.plist                 # launchd plist (used by run_once)
└── scripts/
    ├── migrate-to-chezmoi.sh              # migration script (one-time use)
    └── backup-excludes.txt                # CCC/rsync exclusion list
```

## Managing dotfiles

```zsh
# See what changed on disk vs chezmoi source
chezmoi diff

# Pull changes from disk back into source
chezmoi re-add

# Apply source to disk
chezmoi apply

# Add a new file to chezmoi
chezmoi add ~/.some-config

# Remove a file from chezmoi management
chezmoi forget ~/.some-config

# Undo everything chezmoi has done
chezmoi purge
```
