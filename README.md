# dotfiles — jth Mac Environment

Personal Mac environment as code. One command restores everything on a fresh macOS install.

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

| Component | Tool | Location |
|---|---|---|
| CLI tools, GUI apps, VS Code extensions | Homebrew Bundle | `brewfile/Brewfile` |
| Shell config (zsh, aliases, PATH) | copied directly | `dotfiles/.zshrc` |
| Git identity and config | copied directly | `dotfiles/.gitconfig` |
| Terminal themes (p10k) | copied directly | `dotfiles/.p10k.zsh` |
| Fish shell config | copied directly | `dotfiles/.config/fish/` |
| SSH keys | **manual step** — see below | `dotfiles/.ssh/` |
| AWS credentials | Doppler — see below | — |
| Daily auto-save agent | launchd | `launchagents/com.jth.mac-save.plist` |

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
Installed automatically by `bootstrap.sh`.

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

Or restore from 1Password / a secure location.

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

## Repo Structure

```
dotfiles/
├── README.md                          # this file
├── brewfile/
│   └── Brewfile                       # all packages, casks, extensions
├── dotfiles/
│   ├── .zshrc                         # shell config + all aliases
│   ├── .zshenv / .zprofile            # env vars loaded at login
│   ├── .gitconfig                     # git identity + settings
│   ├── .npmrc                         # npm config
│   ├── .p10k.zsh                      # Powerlevel10k prompt theme
│   ├── .config/fish/                  # fish shell config
│   ├── .config/btop/                  # btop system monitor config
│   ├── .config/kitty/                 # kitty terminal config
│   └── .config/helix/                 # helix editor config (no runtime/)
├── scripts/
│   ├── bootstrap.sh                   # one-command restore script
│   └── backup-excludes.txt            # CCC/rsync exclusion list
└── launchagents/
    └── com.jth.mac-save.plist         # daily auto-save agent
```
