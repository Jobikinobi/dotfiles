# .infisical/ — Infisical Agent Secret Management for Dotfiles

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Human Operator (you)                                        │
│  Creates "dotfiles-provisioner" machine identity in          │
│  Infisical org admin UI. This identity can create projects   │
│  and child identities but CANNOT read any secret values.     │
└──────────────────┬──────────────────────────────────────────┘
                   │ INFISICAL_PROVISIONER_CLIENT_ID/SECRET
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  provision.sh (run once, idempotent)                        │
│  Uses Provisioner to:                                         │
│    1. Ensure projects exist (backend, godocs, mcp-servers)   │
│    2. Create child reader-only machine identities            │
│    3. Age-encrypt child credentials → children/<name>/       │
└──────────────────┬──────────────────────────────────────────┘
                   │ age-encrypted client-id.age / client-secret.age
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  Child Agent Identities (reader-only per project)           │
│                                                             │
│  dotfiles-agent@backend  → reads backend secrets only       │
│  dotfiles-agent@godocs   → reads godocs secrets only        │
│  dotfiles-agent@mcp-servers → reads mcp-servers secrets only│
│                                                             │
│  Each runs as a persistent daemon via infisical agent --config│
│  Templates render secrets into ~/.infisical/*.env files      │
└──────────────────┬──────────────────────────────────────────┘
                   │ rendered env files
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  chezmoi apply                                               │
│    dot_zshrc.tmpl sources ~/.infisical/backend-secrets.env   │
│    scripts read ~/.infisical/godocs-secrets.env              │
│    (no network call needed — files are pre-rendered)         │
└─────────────────────────────────────────────────────────────┘
```

## Security Model

### Provisioner Identity (human-held)
- **Capability:** Create projects, environments, child machine identities
- **Restriction:** Cannot read ANY secret values
- **Storage:** Client ID/Secret held in human's password manager or keychain
- **Never committed to git**

### Child Agent Identities (agent-held)
- **Capability:** Read secrets from ONE project only
- **Restriction:** Cannot create, modify, or delete anything
- **Storage:** Age-encrypted in `.infisical/children/<name>/client-id.age`
- **Each identity is scoped to exactly one project**

### Blast Radius
| Compromised Key | What an Attacker Gets |
|---|---|
| Provisioner | Can create new projects + child IDs, but NO secret values |
| backend/agent | Only POSTMAN_API_KEY, MEM0_API_KEY, TAILSCALE_AUTHKEY_SERVER |
| godocs/agent | Only R2 S3 credentials |
| mcp-servers/agent | Only MCP server secrets |

## Setup Steps

### Step 1: Install Infisical CLI
Already in `dot_Brewfile.core`. After `chezmoi apply`:
```bash
brew install infisical/get-cli/infisical
```

### Step 2: Create the Provisioner Identity
In Infisical Cloud (`app.infisical.com`):
1. Go to **Organization Settings → Access Control → Machine Identities**
2. Click **Create Identity**, name it `dotfiles-provisioner`
3. Assign an organization-level role that allows project creation
4. Add Universal Auth method
5. Generate Client ID + Client Secret
6. Store these in your password manager (they are NEVER committed to git)

### Step 3: Run Provisioning
```bash
export INFISICAL_PROVISIONER_CLIENT_ID="your-client-id"
export INFISICAL_PROVISIONER_CLIENT_SECRET="your-client-secret"
export INFISICAL_AGE_KEY_PATH="$HOME/.config/chezmoi/key.txt"

cd .infisical
./provision.sh
```

This will:
- Create projects if they don't exist
- Create reader-only child identities
- Age-encrypt child credentials into `.infisical/children/<project>/`
- Generate per-project agent configs

### Step 4: Start the Agents
Copy each generated config to your Infisical config directory:
```bash
mkdir -p ~/.config/infisical
cp .infisical/agent-backend.yaml ~/.config/infisical/agent-backend.yaml
cp .infisical/agent-godocs.yaml ~/.config/infisical/agent-godocs.yaml
cp .infisical/agent-mcp-servers.yaml ~/.config/infisical/agent-mcp-servers.yaml
```

Start each agent (or use macOS LaunchAgents for persistence):
```bash
infisical agent --config ~/.config/infisical/agent-backend.yaml &
infisical agent --config ~/.config/infisical/agent-godocs.yaml &
infisical agent --config ~/.config/infisical/agent-mcp-servers.yaml &
```

### Step 5: Verify
```bash
ls ~/.infisical/*-secrets.env
cat ~/.infisical/backend-secrets.env    # Should have export KEY=VALUE lines
```

## Migration from Doppler

The migration happens in phases:

1. **Parallel run** (this branch): Both Doppler and Infisical agents coexist
2. **Template baking**: Replace `{{ output "sh" "-c" "doppler secrets get ..." }}` in `dot_zshrc.tmpl` with sourcing `~/.infisical/backend-secrets.env`
3. **Script migration**: Replace `doppler secrets get` calls in shell scripts with reads from rendered files
4. **Cleanup**: Remove Doppler from Brewfile, update docs

See [../docs/migration-doppler-to-infisical.md](../docs/migration-doppler-to-infisical.md) for the full migration plan.

## Directory Structure

```
.infisical/
├── provision.sh                    # Bootstrap script (Provisioner identity)
├── templates/                      # Go template files for secret rendering
│   ├── backend-secrets.tpl
│   ├── godocs-secrets.tpl
│   └── mcp-servers-secrets.tpl
├── children/                       # Age-encrypted child credentials (gitignored)
│   ├── backend/
│   │   ├── client-id.age
│   │   └── client-secret.age
│   ├── godocs/
│   │   └── ...
│   └── mcp-servers/
│       └── ...
├── agent-backend.yaml              # Per-project agent config (generated by provision.sh)
├── agent-godocs.yaml
└── agent-mcp-servers.yaml
```
