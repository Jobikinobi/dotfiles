# Personal Codespaces on Proxmox

Self-hosted, browser-accessible development platform. Coder provides the
control plane (login, dashboard, workspace lifecycle); Docker on the same
VM provides the workspace compute; Postgres holds Coder's state.

This document covers the **first VM only** (`dev-control` at .20). Incus
and IncusOS experiments at .21 and .22 are tracked separately — see
[Roadmap](#roadmap).

## Target architecture

```
Proxmox host (pve, 192.168.68.16)
└── VM: dev-control (192.168.68.20)
    ├── Ubuntu Server 24.04 LTS
    ├── Docker Engine
    ├── PostgreSQL 16 (host-installed; Coder state)
    ├── Coder (docker run, ghcr.io/coder/coder:latest)
    └── Workspace containers (per-user, spawned by Coder)
        ├── code-server (browser IDE)
        ├── persistent volumes
        └── devcontainer-compatible
```

VM, not LXC. Coder workspaces nest Docker; LXC + nested Docker introduces
privilege/cgroup issues that are not worth debugging for a first build.

## Prerequisites

- PVE reachable: `ssh pve` works (see `private_dot_ssh/config.tmpl`)
- LAN: `192.168.68.0/24`, gateway `.1`, no DHCP reservation conflict at `.20`
- Ubuntu 24.04 cloud image template available on PVE (or willing to upload one)

## Build steps (hand-run from this runbook)

### 1. Create the VM on Proxmox

From `ssh pve`:

```bash
# Adjust storage name (local-lvm), bridge (vmbr0), and template path to match your PVE
qm create 120 \
  --name dev-control \
  --memory 8192 \
  --cores 4 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --ostype l26 \
  --agent enabled=1
```

Attach the Ubuntu 24.04 cloud-init disk, set ciuser/cipassword/sshkey, and
configure static IP `192.168.68.20/24` via cloud-init network config.

Start it, wait for cloud-init to settle, confirm `ssh dev-control` works
once the SSH stub from `private_dot_ssh/config.tmpl` is materialized.

### 2. Apply dotfiles

```bash
ssh dev-control
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Jobikinobi
```

Linux bootstrap (Tailscale, Homebrew core, Brewfile) is handled by the
existing `run_once_before_install-toolchains.sh.tmpl` and
`run_once_after_install-brewfile.sh.tmpl`.

### 3. Install Docker

```bash
# Official convenience script — Docker maintains it; fine for a single VM
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# log out / back in for group membership
```

### 4. Install Postgres 16 (host)

```bash
sudo apt update && sudo apt install -y postgresql-16
sudo -u postgres createuser --pwprompt coder
sudo -u postgres createdb -O coder coder
```

Store the password in Doppler (`dotfiles config` project), key
`CODER_PG_PASSWORD`. Don't commit it.

### 5. Run Coder

```bash
export DOCKER_GROUP=$(getent group docker | cut -d: -f3)
docker run -d --name coder --restart unless-stopped \
  -p 7080:7080 \
  -e CODER_HTTP_ADDRESS=0.0.0.0:7080 \
  -e CODER_ACCESS_URL="http://192.168.68.20:7080" \
  -e CODER_PG_CONNECTION_URL="postgresql://coder:${CODER_PG_PASSWORD}@host.docker.internal:5432/coder?sslmode=disable" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --add-host=host.docker.internal:host-gateway \
  --group-add $DOCKER_GROUP \
  ghcr.io/coder/coder:latest
```

Browse to `http://192.168.68.20:7080`, complete first-user setup. The
admin email/password go into Doppler, not this repo.

### 6. Create the first workspace template

Use Coder's "Docker" starter template via the UI. Confirm a workspace
spawns, code-server loads in the browser, and a persistent volume
survives a workspace restart.

## TLS / reverse proxy

Deliberately deferred. LAN-only HTTP is acceptable for the first iteration.
Once the manual path is proven end-to-end, follow up with either:

- Caddy on the VM with a `*.lan.lemming-likert.ts.net` cert via Tailscale, or
- Tailscale Funnel for the access URL (changes `CODER_ACCESS_URL`)

Don't add TLS before the bare path works.

## Roadmap

| VM | IP | Role | Status |
|---|---|---|---|
| dev-control | .20 | Coder + Docker + Postgres | this PR |
| incus-lab | .21 | Ubuntu VM running Incus, evaluate as workspace backend | follow-up |
| incusos-lab | .22 | IncusOS appliance in a VM, evaluate vs. plain Incus | follow-up |

Each follow-up is its own PR. Do not bundle.

## Operational notes

- Coder data lives in Postgres on the VM. Add to PVE's backup schedule
  once it's running.
- Docker images Coder pulls for workspaces accumulate; `docker system prune`
  monthly until a real policy exists.
- The encrypted appendix (`~/.local/share/infra/personal-codespaces.md`)
  will hold Coder admin credentials, Postgres password reference, and
  exact VMIDs once the VM is built — created in the follow-up PR.
