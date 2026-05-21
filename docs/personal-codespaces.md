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
└── VM: dev-control (192.168.68.20, 8 vCPU / 32 GB / 300 GB)
    ├── Ubuntu Server 24.04 LTS (cloud-init)
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
- LAN: `192.168.68.0/22`, gateway `.1`, no DHCP reservation conflict at `.20`
  (the /22 isn't a typo — the Eero hands out a /22 spanning .68.0–.71.255)
- Ubuntu 24.04 cloud-init **template** on PVE (Phase 0 below builds one if missing —
  a plain ISO in `/var/lib/vz/template/iso/` is *not* the same thing)
- SSH keypair `id_ed25519_dev_control` exists on this Mac. The SSH stub in
  `private_dot_ssh/config.tmpl` already references it; Phase 2 ships the
  public half to the VM via cloud-init. Generate before Phase 2:

  ```bash
  test -f ~/.ssh/id_ed25519_dev_control || \
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_dev_control -N '' \
      -C "jth@dev-control"
  ```

## Build steps (hand-run from this runbook)

### Phase 0 — Proxmox readiness audit (read-only)

Before any `qm create`, confirm the host is administered enough to accept
the VM. Run from `ssh pve`:

```bash
# Node + version
pveversion --verbose
pvesh get /nodes/pve/status --output-format json | jq '{uptime,cpu,memory,rootfs}'

# Storage: identify where VM disks, ISOs, and cloud-init snippets live
pvesm status
pvesh get /storage --output-format json | jq '.[] | {storage,type,content}'

# Network: confirm the bridge name (default vmbr0) and any SDN vnets
pvesh get /nodes/pve/network --output-format json | jq '.[] | {iface,type,active,address}'
pvesh get /cluster/sdn/vnets 2>/dev/null  # empty/error is fine if SDN unused

# Existing VMs / templates — note any template with cloud-init already wired
qm list

# Is .20 actually free on the LAN?
ip neigh | grep '192\.168\.68\.20' || echo "ok: .20 not in ARP cache"
```

Capture which storage to use for the VM disk (typical: `local-lvm` for
block, `local` for ISOs/snippets). If `local` doesn't list `snippets` in
its `content` column, enable it via Datacenter → Storage → local → Edit
before cloud-init custom configs will work.

### Phase 1 — Build the Ubuntu 24.04 cloud-init template (skip if Phase 0 found one)

A cloud image is **not** an ISO. The `.img` is a pre-installed qcow2 that
cloud-init configures on first boot. The user's PVE has Ubuntu ISOs but
no cloud-init template yet, so build one. VMID 9000 is the convention for
templates. Replace `<storage>` with whatever Phase 0 identified as the
block storage for VM disks (commonly `local-lvm`):

```bash
# On pve
cd /var/lib/vz/template/iso/
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

qm create 9000 --name ubuntu-2404-cloud --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --ostype l26 \
  --serial0 socket --vga serial0 --agent enabled=1
qm importdisk 9000 noble-server-cloudimg-amd64.img <storage>
qm set 9000 --scsi0 <storage>:vm-9000-disk-0,discard=on,ssd=1
qm set 9000 --ide2 <storage>:cloudinit --boot c --bootdisk scsi0
qm template 9000
```

### Phase 2 — Clone the template into dev-control (VMID 120)

```bash
# On pve — same <storage> as Phase 1
qm clone 9000 120 --name dev-control --full --storage <storage>
qm resize 120 scsi0 300G          # cloud image ships at ~2.2 GB
qm set 120 --cores 8 --memory 32768 --sockets 1 --cpu host
qm set 120 --ipconfig0 ip=192.168.68.20/22,gw=192.168.68.1
qm set 120 --nameserver 192.168.68.1  # add --searchdomain only if the LAN has one
qm set 120 --ciuser jth
qm set 120 --sshkeys ~/.ssh/id_ed25519_dev_control.pub  # generate first if missing
qm start 120
```

Wait for cloud-init to settle (~60s after boot), then on this Mac:

```bash
ssh dev-control  # uses the stub already in private_dot_ssh/config.tmpl
```

### Phase 3 — Apply dotfiles

```bash
ssh dev-control
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Jobikinobi
```

Linux bootstrap (Tailscale, Homebrew core, Brewfile) is handled by the
existing `run_once_before_install-toolchains.sh.tmpl` and
`run_once_after_install-brewfile.sh.tmpl`.

### Phase 4 — Install Docker

```bash
# Official convenience script — Docker maintains it; fine for a single VM
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# log out / back in for group membership
```

### Phase 5 — Install Postgres 16 (host)

```bash
sudo apt update && sudo apt install -y postgresql-16
sudo -u postgres createuser --pwprompt coder
sudo -u postgres createdb -O coder coder
```

Password handling — **don't rely on Doppler here**: the project's known
issue (dotfiles#5) is that Doppler's keyring is inaccessible over SSH,
which is the only way we administer this VM. For Phase 5/6, write the
password into `/etc/coder/coder.env` (root:root, 0600) and source it from
the Coder unit:

```bash
sudo install -d -m 0750 -o root -g root /etc/coder
sudo tee /etc/coder/coder.env >/dev/null <<'EOF'
CODER_PG_PASSWORD=<paste-once-here>
EOF
sudo chmod 0600 /etc/coder/coder.env
```

The canonical copy still lives in Doppler (`dotfiles config`, key
`CODER_PG_PASSWORD`) — `/etc/coder/coder.env` is the runtime cache.

### Phase 6 — Run Coder

```bash
set -a; source /etc/coder/coder.env; set +a
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

**Docker socket caveat:** binding `/var/run/docker.sock` into Coder is
root-equivalent on the VM. That's acceptable because dev-control is a
single-tenant VM — only jth uses it — and Coder needs the socket to
spawn workspace containers. Do *not* reproduce this pattern in a
multi-tenant context without a socket proxy in front.

Browse to `http://192.168.68.20:7080`, complete first-user setup. The
admin email/password go into Doppler, not this repo.

### Phase 7 — Create the first workspace template

Use Coder's "Docker" starter template via the UI. Confirm a workspace
spawns, code-server loads in the browser, and a persistent volume
survives a workspace restart.

## Done-when checklist

The "Personal Codespaces Core" milestone is complete when *all* of these
pass — partial completion is not done:

- [ ] Coder reachable on LAN at `http://192.168.68.20:7080`
- [ ] Admin account created, credentials stored in Doppler
- [ ] Postgres data survives `docker restart coder` and a VM reboot
- [ ] One Docker workspace template published
- [ ] Browser code-server loads in the workspace
- [ ] GitHub auth works inside the workspace (SSH key or PAT)
- [ ] A repo clones, a dev server starts, the preview port is reachable
      through Coder's port-forwarding
- [ ] Workspace state persists across stop/start
- [ ] PVE snapshot taken of VMID 120; restore verified at least once

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
  will hold operational details once the VM is built — exact VMIDs,
  storage names chosen in Phase 0, Doppler key names for the Coder admin
  user and Postgres password. Doppler remains the source of truth for the
  secret values themselves; the appendix points to them.
